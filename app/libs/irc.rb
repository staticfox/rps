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

  def add_client server_sid, sid, nick, modes, user, host, real
    @bots.each { |bot| return -1 if bot["nick"] == nick }

    send_data @name, @sock, ":#{server_sid} EUID #{nick} 2 #{Time.now.to_i} #{modes} #{user} #{host} 0 #{sid} * * :#{real}\r\n"

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

  def client_part_channel sid, room
    send_data @name, @sock, ":#{sid} PART #{room}\r\n"
    UserInChannel.establish_connection(@db)
    userinchannel = UserInChannel.where("User = ? AND Channel = ?", sid, room)
    userinchannel.delete_all
    UserInChannel.connection.disconnect!
  end

  def privmsg sid, target, message
    send_data @name, @sock, ":#{sid} PRIVMSG #{target} :#{message}\r\n"
  end

  def notice sid, target, message
    send_data @name, @sock, ":#{sid} NOTICE #{target} :#{message}\r\n"
  end

  def get_uid_object uid
    User.establish_connection(@db)
    user = User.connection.select_all("SELECT `UModes` FROM `users` WHERE `UID` = '#{uid}';")

    user.each { |info|
      User.connection.disconnect!
      return info
    }

    return false
  end

  def get_nick_object nick
    User.establish_connection(@db)
    user = User.connection.select_all("SELECT `UID` FROM `users` WHERE `Nick` = '#{nick}';")

    user.each { |info|
    User.connection.disconnect!
      return info["UID"]
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
