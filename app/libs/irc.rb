require 'active_record'

class User < ActiveRecord::Base
end

class Channel < ActiveRecord::Base
end

class UserInChannel < ActiveRecord::Base
end

class IRCLib

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def add_client server_sid, sid, server, nick, modes, user, host, real, account = "*"
    @bots.each { |bot| return -1 if bot["nick"] == nick }

    User.establish_connection(@db)

    db_add          = User.new
    db_add.Nick     = nick
    db_add.CTime    = Time.now.to_i
    db_add.UModes   = modes
    db_add.Ident    = user
    db_add.CHost    = "*"
    db_add.IP       = 0
    db_add.UID      = sid
    db_add.Host     = host
    db_add.Server   = server
    db_add.NickServ = account
    db_add.save
    User.connection.disconnect!

    send_data @name, @sock, ":#{server_sid} EUID #{nick} 2 #{Time.now.to_i} #{modes} #{user} #{host} 0 #{sid} * #{account} :#{real}\r\n"

    hash = {"name" => @name, "sock" => @sock, "nick" => nick, "user" => user, "host" => host, "sid" => sid, "server_sid" => server_sid, "real" => real, "modes" => modes}
    @bots.push(hash)
  end

  def remove_client sid, msg = nil
    @bots.each { |bot|
      send_data @name, @sock, ":#{sid} QUIT :#{msg}\r\n" if bot["sid"] == sid
      @bots.delete bot if bot["sid"] == sid
    }
    return -1
  end

  def server_set_mode server_sid, string
    ts = Time.now.to_i
    send_data @name, @sock, ":#{server_sid} TMODE #{ts} #{string}\r\n"
  end

  def client_set_mode sid, string
    send_data @name, @sock, ":#{sid} MODE #{string}\r\n"
  end

  def client_join_channel sid, room
    ts = Time.now.to_i
    send_data @name, @sock, ":#{sid} JOIN #{ts} #{room} +\r\n"
    UserInChannel.establish_connection(@db)
    userinchannel = UserInChannel.new
    userinchannel.Channel = room
    userinchannel.User = sid
    userinchannel.Modes = ""
    userinchannel.save
    UserInChannel.connection.disconnect!
  end

  def client_part_channel sid, room, reason = ""
    send_data @name, @sock, ":#{sid} PART #{room} :#{reason}\r\n"
    UserInChannel.establish_connection(@db)
    userinchannel = UserInChannel.where("User = ? AND Channel = ?", sid, room)
    userinchannel.delete_all
    UserInChannel.connection.disconnect!
  end

  def privmsg sid, target, message
    data = message.split("\n")
    if data.nil?
      message.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{sid} PRIVMSG #{target} :#{x}\r\n" }
    else
      data.each { |d|
        if d.is_a? String
          d.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{sid} PRIVMSG #{target} :#{x}\r\n" }
        else
          d.each { |f| f.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{sid} PRIVMSG #{target} :#{x}\r\n" } }
        end
      }
    end
  end

  def notice sid, target, message
    data = message.split("\n")
    if data.nil?
      message.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{sid} NOTICE #{target} :#{x}\r\n" }
    else
      data.each { |d|
        if d.is_a? String
          d.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{sid} NOTICE #{target} :#{x}\r\n" }
        else
          d.each { |f| f.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{sid} NOTICE #{target} :#{x}\r\n" } }
        end
      }
    end
  end

  def wallop sid, message
    send_data @name, @sock, ":#{sid} OPERWALL :#{message}\r\n"
  end

  def squit sid, message
    send_data @name, @sock, "SQUIT #{sid} :#{message}\r\n"
  end

  def ts6_fnc sid, newnick, uobj
    send_data @name, @sock, ":#{sid} ENCAP #{uobj["Server"]} RSFNC #{uobj["UID"]} #{newnick} #{Time.now.to_i} #{uobj["CTime"]}\r\n"
    change_nick newnick, uobj["UID"]
  end

  def kill sobj, uid, message
    send_data @name, @sock, ":#{sobj["UID"]} KILL #{uid} :#{sobj["Host"]}!#{sobj["Nick"]} (#{message})\r\n"
    delete_user uid
  end

  def get_user_channels uid
    UserInChannel.establish_connection(@db)
    data = UserInChannel.where("User = ?", uid)
    chans = []
    data.each { |i|
      pfx = ""
      if !i["Modes"].empty?
        i["Modes"].split(//).each { |x|
          case x
          when "v"
            pfx += "+"
          when "h"
            pfx += "%"
          when "o"
            pfx += "@"
          when "a"
            pfx += "&"
          when "q"
            pfx += "~"
          end
        }
      end
      chans << pfx+i["Channel"].to_s
    }
    UserInChannel.connection.disconnect!
    return chans
  end

  def delete_user uid
    User.establish_connection(@db)
    user = User.where('UID = ?', uid)
    user.delete_all

    UserInChannel.establish_connection(@db)
    channel = UserInChannel.where("User = ?", uid)
    channel.delete_all
    User.connection.disconnect!
    UserInChannel.connection.disconnect!
  end

  def change_nick nick, uid
    User.establish_connection(@db)
    nickd = User.sanitize nick
    nickuid = User.sanitize uid
    User.connection.execute("UPDATE `users` SET `Nick` = #{nickd} WHERE `UID` = #{nickuid};")
    User.connection.disconnect!
  end

  def get_uid_object uid
    User.establish_connection(@db)
    user = User.connection.select_all("SELECT * FROM `users` WHERE `UID` = '#{uid}';")

    user.each { |info|
      User.connection.disconnect!
      return info
    }

    return false
  end

  def get_nick_object nick
    User.establish_connection(@db)
    user = User.connection.select_all("SELECT * FROM `users` WHERE `Nick` = '#{nick}';")

    user.each { |info|
      User.connection.disconnect!
      return info
    }

    return false
  end

  def get_channel_membership channel, uid
    UserInChannel.establish_connection(@db)
    userinchannel = UserInChannel.connection.select_all("SELECT `Modes` FROM `user_in_channels` WHERE `Channel` = '#{channel}' AND `User` = '#{uid}';")

    userinchannel.each { |info|
      UserInChannel.connection.disconnect!
      return info
    }

    return false
  end

  def get_nick_from_uid uid
    uid_object = get_uid_object uid
    return false if !uid_object

    return uid_object["Nick"]
  end

  def get_uid_from_nick nick
    nick_object = get_nick_object nick
    return false if !nick_object

    return nick_object["UID"]
  end

  def is_oper_uid uid
    uid_object = get_uid_object uid
    return false if !uid_object

    return true if uid_object["UModes"].include?("o")
    return false
  end

  def is_oper_nick nick
    nick_object = get_nick_object nick
    return false if !nick_object

    return true if nick_object["UModes"].include?("o")
    return false
  end

  def is_chan_founder channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access["Modes"].include?("q")
    return false
  end

  def is_chan_admin channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access["Modes"].include?("a")
    return false
  end

  def is_chan_op channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access["Modes"].include?("o")
    return false
  end

  def is_chan_halfop channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access["Modes"].include?("h")
    return false
  end

  def is_chan_voice channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access["Modes"].include?("v")
    return false
  end

  def is_user_ssl_connected uid
    uid_object = get_uid_object uid
    return false if !uid_object

    return true if uid_object["UModes"].include?("Z")
    return false
  end

  def get_account_from_uid uid
    uid_object = get_uid_object uid
    return false if !uid_object

    return false if uid_object["NickServ"] == '*'
    return uid_object["NickServ"]
  end

  def get_chan_info channel
    cd = {}
    Channel.establish_connection(@db)
    channel = Channel.where('Channel = ?', channel.downcase)
    if channel.count == 0
      Channel.connection.disconnect!
      return false
    end
    channel.each { |q|
      cd[:channel] = q.Channel
      cd[:ctime]   = q.CTime
      cd[:modes]   = q.Modes
      Channel.connection.disconnect!
      return cd
    }
    return false
  end

  def get_users_in_channel channel
    users = []
    UserInChannel.establish_connection(@db)
    uic = UserInChannel.where('Channel = ?', channel.downcase)
    uic.each { |query|
      pfx = ""
      if !query["Modes"].empty?
        query["Modes"].split(//).each { |x|
          case x
          when "v"
            pfx += "+"
          when "h"
            pfx += "%"
          when "o"
            pfx += "@"
          when "a"
            pfx += "&"
          when "q"
            pfx += "~"
          end
        }
      end
      uobj = get_uid_object query["User"]
      next if !uobj
      users << "#{pfx}#{uobj["Nick"]}!#{uobj["Ident"]}@#{uobj["IP"]}"
    }

    # FIXME
    u2 = []
    users.sort!
    users.each { |c| u2 << c if c[0] == '~' }
    users.each { |c| u2 << c if c[0] == '&' }
    users.each { |c| u2 << c if c[0] == '@' }
    users.each { |c| u2 << c if c[0] == '%' }
    users.each { |c| u2 << c if c[0] == '+' }
    users.each { |c| u2 << c if c[0] =~ /[a-zA-Z]/ }
    return u2
  end

  def people_in_channel channel
    UserInChannel.establish_connection(@db)
    userinchannel = UserInChannel.connection.select_all("SELECT COUNT(*) AS `Total` FROM `user_in_channels` WHERE `Channel` = '#{channel.downcase}';")
    userinchannel.each { |query|
      UserInChannel.connection.disconnect!
      return query["Total"]
    }
  end

  def get_channels
    channellist = []
    Channel.establish_connection(@db)
    channels = Channel.select(:Channel).distinct
    channels.each { |channel| channellist.push(channel.Channel) }
    Channel.connection.disconnect!
    return channellist
  end

  def does_channel_exist channel
    Channel.establish_connection(@db)
    channel = Channel.where('Channel = ?', channel.downcase)
    return true if channel.count >= 1
    Channel.connection.disconnect!
    return false
  end

  def initialize name, sock, db
    @name = name
    @sock = sock
    @bots = []
    @db = db

    User.establish_connection(@db)
    User.connection.disconnect!
    Channel.establish_connection(@db)
    Channel.connection.disconnect!
    UserInChannel.establish_connection(@db)
    UserInChannel.connection.disconnect!
  end
end
