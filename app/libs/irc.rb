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

  def add_client server_sid, sid, server, nick, modes, user, host, real
    @bots.each { |bot| return -1 if bot["nick"] == nick }

    User.establish_connection(@db)

    db_add          = User.new
    db_add.nick     = nick
    db_add.ctime    = Time.now.to_i
    db_add.umodes   = modes.tr('+', '')
    db_add.ident    = user
    db_add.chost    = host
    db_add.ip       = 0
    db_add.uid      = sid
    db_add.host     = '*'
    db_add.server   = server
    db_add.nickserv = '*'
    db_add.save
    User.connection.disconnect!

    send_data @name, @sock, ":#{server_sid} EUID #{nick} 2 #{Time.now.to_i} #{modes} #{user} #{host} 0 #{sid} * * :#{real}\r\n"

    hash = {"name" => @name, "sock" => @sock, "nick" => nick, "user" => user, "host" => host, "sid" => sid, "server" => server, "server_sid" => server_sid, "real" => real, "modes" => modes}
    @bots.push(hash)
  end

  def remove_client sid, msg = nil
    @bots.each { |bot|
      send_data @name, @sock, ":#{sid} QUIT :#{msg}\r\n" if bot["sid"] == sid
      @bots.delete bot if bot["sid"] == sid
    }
    return -1
  end

  def collide nick, server
    User.establish_connection(@db)
    user = User.where(nick: nick)

    @bots.each { |bot|
      user.each { |info|
        if bot["nick"].downcase == info[:nick].downcase
          if bot["server"].downcase != info[:server].downcase
            server_kill bot["server_sid"], info[:uid], bot["server"], "Nick collision with services (new)"
            nick bot["sid"], bot["nick"]
          end
        end
      }
    }

    User.connection.disconnect!
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
    UserInChannel.establish_connection(@db)
    exists = UserInChannel.where(user: sid, channel: room)
    if exists.count > 0
      UserInChannel.connection.disconnect!
      return
    end
    send_data @name, @sock, ":#{sid} JOIN #{ts} #{room} +\r\n"
    userinchannel = UserInChannel.new
    userinchannel.channel = room
    userinchannel.user = sid
    userinchannel.modes = "o"
    userinchannel.save
    UserInChannel.connection.disconnect!
  end

  def client_part_channel sid, room, reason = ""
    send_data @name, @sock, ":#{sid} PART #{room} :#{reason}\r\n"
    UserInChannel.establish_connection(@db)
    userinchannel = UserInChannel.where(user: sid, channel: room)
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

  def unkline sid, ip
    send_data @name, @sock, ":#{sid} UNKLINE * * #{ip}\r\n"
  end

  def chghost serversid, uid, host
    send_data @name, @sock, ":#{serversid} CHGHOST #{uid} #{host}\r\n"
    User.establish_connection(@db)
    query = User.find_by(uid: uid)
    query.update(chost: host)
    User.connection.disconnect!
  end

  def ts6_fnc sid, newnick, uobj
    send_data @name, @sock, ":#{sid} ENCAP #{uobj[:server]} RSFNC #{uobj[:uid]} #{newnick} #{Time.now.to_i} #{uobj[:ctime]}\r\n"
  end

  def ts6_save sid, uobj
    send_data @name, @sock, ":#{sid} SAVE #{uobj[:uid]} #{uobj[:ctime]}\r\n"
    change_nick uobj[:uid], uobj[:uid]
  end

  def server_kill sid, uid, server_name, reason
    send_data @name, @sock, ":#{sid} KILL #{uid} :#{server_name} (#{reason})\r\n"
    delete_user uid
  end

  def kill sobj, uid, message
    send_data @name, @sock, ":#{sobj[:uid]} KILL #{uid} :#{sobj[:host]}!#{sobj[:nick]} (#{message})\r\n"
    delete_user uid
  end

  def kick ouruid, theiruid, channel, message
    send_data @name, @sock, ":#{ouruid} KICK #{channel} #{theiruid} :#{message}\r\n"
    remove_user_from_channel theiruid, channel
  end

  def nick sid, newnick
    send_data @name, @sock, ":#{sid} NICK #{newnick} :#{Time.new.to_i}"
    change_nick newnick, sid
  end

  def remove_user_from_channel uid, channel
    UserInChannel.establish_connection(@db)
    userinchannel = UserInChannel.where(user: uid, channel: channel)
    userinchannel.delete_all
    UserInChannel.connection.disconnect!
  end

  def get_user_channels uid
    UserInChannel.establish_connection(@db)
    data = UserInChannel.where(user: uid)
    chans = []
    data.each { |i|
      pfx = ""
      if !i[:modes].empty?
        i[:modes].split(//).each { |x|
          case x
          when "v"
            pfx += "+" if pfx.empty?
          when "h"
            pfx += "%" if pfx.empty?
          when "o"
            pfx += "@" if pfx.empty?
          when "a"
            pfx += "&" if pfx.empty?
          when "q"
            pfx += "~" if pfx.empty?
          end
        }
      end
      if get_chan_info(i[:channel])[:modes].include? 's'
        pfx = '*'+pfx
      end
      chans << pfx+i[:channel].to_s
    }
    UserInChannel.connection.disconnect!
    return chans
  end

  def delete_user uid
    User.establish_connection(@db)
    user = User.where(uid: uid)
    user.delete_all

    UserInChannel.establish_connection(@db)
    channel = UserInChannel.where(user: uid)
    channel.delete_all
    User.connection.disconnect!
    UserInChannel.connection.disconnect!
  end

  def change_nick nick, uid
    User.establish_connection(@db)
    query = User.find_by(uid: uid)
    query.update(nick: nick, ctime: Time.new.to_i)
    User.connection.disconnect!
  end

  def get_uid_object uid
    User.establish_connection(@db)
    user = User.where(uid: uid).first
    User.connection.disconnect!
    return user
  end

  def get_nick_object nick
    User.establish_connection(@db)
    user = User.where(nick: nick).first
    User.connection.disconnect!
    return user
  end

  def get_channel_membership channel, uid
    UserInChannel.establish_connection(@db)
    userinchannel = UserInChannel.select(:modes).where(channel: channel, user: uid).first
    UserInChannel.connection.disconnect!
    return userinchannel
  end

  def get_nick_from_uid uid
    uid_object = get_uid_object uid
    return false if !uid_object

    return uid_object[:nick]
  end

  def get_uid_from_nick nick
    nick_object = get_nick_object nick
    return false if !nick_object

    return nick_object[:uid]
  end

  def is_oper_uid uid
    uid_object = get_uid_object uid
    return false if !uid_object

    return true if uid_object[:umodes].include?("o")
    return false
  end

  def is_oper_nick nick
    nick_object = get_nick_object nick
    return false if !nick_object

    return true if nick_object[:umodes].include?("o")
    return false
  end

  def is_chan_founder channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access[:modes].include?("q")
    return false
  end

  def is_chan_admin channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access[:modes].include?("a")
    return false
  end

  def is_chan_op channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access[:modes].include?("o")
    return false
  end

  def is_chan_halfop channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access[:modes].include?("h")
    return false
  end

  def is_chan_voice channel, uid
    chan_access = get_channel_membership channel, uid
    return false if !chan_access

    return true if chan_access[:modes].include?("v")
    return false
  end

  def is_user_ssl_connected uid
    uid_object = get_uid_object uid
    return false if !uid_object

    return true if uid_object[:umodes].include?("Z")
    return false
  end

  def get_account_from_uid uid
    uid_object = get_uid_object uid
    return false if !uid_object

    return false if uid_object[:nickserv] == '*'
    return uid_object[:nickserv]
  end

  def get_chan_info channel
    Channel.establish_connection(@db)
    channel = Channel.where(channel: channel.downcase)
    if channel.count == 0
      Channel.connection.disconnect!
      return false
    end
    channel.each { |q|
      Channel.connection.disconnect!
      return q
    }
    return false
  end

  def get_users_in_channel channel
    users = []
    UserInChannel.establish_connection(@db)
    uic = UserInChannel.where(channel: channel.downcase)
    uic.each { |query|
      pfx = ""
      if !query[:modes].empty?
        query[:modes].split(//).each { |x|
          case x
          when "v"
            pfx += "+" if pfx.empty?
          when "h"
            pfx += "%" if pfx.empty?
          when "o"
            pfx += "@" if pfx.empty?
          when "a"
            pfx += "&" if pfx.empty?
          when "q"
            pfx += "~" if pfx.empty?
          end
        }
      end
      uobj = get_uid_object query[:user]
      next if !uobj
      ip = uobj[:ip] != '0' ? uobj[:ip] : uobj[:chost]
      users << "#{pfx}#{uobj[:nick]} [#{uobj[:ident]}@#{ip}]"
    }

    # FIXME
    u2 = []
    users = users.sort_by{|w| w.downcase}
    users.each { |c| u2 << c if c[0] == '~' }
    users.each { |c| u2 << c if c[0] == '&' }
    users.each { |c| u2 << c if c[0] == '@' }
    users.each { |c| u2 << c if c[0] == '%' }
    users.each { |c| u2 << c if c[0] == '+' }
    users.each { |c| u2 << c if !['~', '&', '@', '%', '+'].include? c[0] }
    return u2
  end

  def people_in_channel channel
    UserInChannel.establish_connection(@db)
    query = UserInChannel.where(channel: channel.downcase).count
    UserInChannel.connection.disconnect!
    return query
  end

  def get_channels
    channellist = []
    Channel.establish_connection(@db)
    channels = Channel.select(:channel).distinct
    channels.each { |channel| channellist.push(channel.channel) }
    Channel.connection.disconnect!
    return channellist
  end

  def get_channel_total
    Channel.establish_connection(@db)
    channels = Channel.select(:channel).count
    Channel.connection.disconnect!
    return channels
  end

  def get_user_total
    User.establish_connection(@db)
    users = User.select(:nick).count
    User.connection.disconnect!
    return users
  end

  def get_oper_total
    i = 0
    User.establish_connection(@db)
    User.select(:umodes).each { |d|
      i+=1 if d[:umodes].include? 'o' or d[:umodes].include? 'O' and !d[:umodes].include? 'S'
    }
    User.connection.disconnect!
    return i
  end

  def get_services_total
    i = 0
    User.establish_connection(@db)
    User.select(:umodes).each { |d| i+=1 if d[:umodes].include? 'S' }
    User.connection.disconnect!
    return i
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
