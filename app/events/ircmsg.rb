require 'active_record'

class User < ActiveRecord::Base
end

class Channel < ActiveRecord::Base
end

class UserInChannel < ActiveRecord::Base
end

class IRCMsg

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def send_message name, sock, cmd, target, string
    send_data name, sock, "#{cmd} #{target} :#{string}\r\n"
  end

  def handle_chat name, sock, line
    irc_split  = line.split(/^(?:[:](\S+) )?(\S+)(?: (?!:)(.+?))?(?: [:](.+))?$/)
    person     = irc_split[1]
    msgtype    = irc_split[2]
    target     = irc_split[3]
    command    = irc_split[4].split(' ')[0]
    return if command.nil?
    parameters = irc_split[4].split(' ')[1..-1].join(' ')

    hash = {"name" => name, "sock" => sock, "msgtype" => msgtype, "from" => person, "target" => target, "command" => command, "parameters" => parameters}
    @e.Run "IRCChat", hash
  end

  def handle_ping name, sock, line
    send_data name, sock, "PONG :#{line[6..-1]}\r\n"
    @e.Run "IRCPing", name, sock, line
  end

  def handle_numeric name, sock, line, numeric
    hash = {"name" => name, "sock" => sock, "line" => line, "numeric" => numeric}
    @e.Run "IRCNumeric", hash
  end

  def handle_euid name, sock, data
    return if data.include?("ENCAP * GCAP :") or data.include?(" ENCAP ")
    data = data.split(' ')

    User.establish_connection(@config["connections"]["databases"]["test"])

    user = User.new
    user.Nick   = data[2] ? data[2] : ""
    user.CTime  = data[4] ? data[4] : ""
    user.UModes = data[5][1..-1] ? data[5][1..-1] : ""
    user.Ident  = data[6] ? data[6] : ""
    user.CHost  = data[7] ? data[7] : ""
    user.IP     = data[8] ? data[8] : ""
    user.UID    = data[9] ? data[9] : ""
    user.Host   = data[10] ? data[10] : ""
    @ircservers.each do |hash|
      user.Server = hash["server"] if data[0][1..-1] == hash["SID"]
    end

    user.Server = "irc.geeksirc.net" if user.Server.nil?
    user.NickServ = data[11]
    user.save
    User.connection.disconnect!
  end

  def handle_sjoin name, sock, data
    users = data.split(':')[-1]
    data  = data.split(' ')

    Channel.establish_connection(@config["connections"]["databases"]["test"])
    channel = Channel.new
    channel.CTime = data[2]
    thechannel = data[3]
    channel.Channel = data[3]
    channel.Modes = data[4]
    channel.save
    Channel.connection.disconnect!

    if !users.nil? and !users.include? ' SJOIN '
      users = users.split(' ')
      UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
      users.each do |user|
        modes = ""
        modes << "q" if user.include?("~")
        modes << "a" if user.include?("&")
        modes << "o" if user.include?("@")
        modes << "h" if user.include?("%")
        modes << "v" if user.include?("+")
        length = modes.length
        nickname = user[length..-1]
        userinchannel = UserInChannel.new
        userinchannel.Channel = thechannel
        userinchannel.User = nickname
        userinchannel.Modes = modes
        userinchannel.save
      end
      UserInChannel.connection.disconnect!
    end
    @e.Run "IRCChanSJoin", name, sock, data
  end

  def handle_sid name, sock, data
    data = data.split(' ')
    hash = {"SID" => data[4], "server" => data[2]}
    #puts hash
    @ircservers.push(hash)
  end

  def handle_pass name, sock, data
    data = data.split(' ')
    hash = {"SID" => data[4][1..-1], "server" => "rpsuplink"}
    @ircservers.push(hash)
  end

  def handle_server name, sock, data
    server = data.split(' ')[1]
    @ircservers.collect { |hash|
      if hash["server"] == "rpsuplink"
        hash["server"] = server
        puts "set #{hash["SID"]} to #{server}"
      end
    }
  end

  def handle_quit name, sock, data
    data = data.split(' ')
    nick = data[0][1..-1]

    User.establish_connection(@config["connections"]["databases"]["test"])
    user = User.where('UID = ?', nick)
    user.delete_all

    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    channel = UserInChannel.where("User = ?", nick)
    channel.delete_all
    User.connection.disconnect!
    UserInChannel.connection.disconnect!

    @e.Run "IRCClientQuit", name, sock, data
  end

  def handle_join name, sock, data
    data = data.split(' ')
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    userinchannel = UserInChannel.new
    userinchannel.Channel = data[3]
    userinchannel.User = data[0][1..-1]
    userinchannel.Modes = ""
    userinchannel.save
    @e.Run "IRCChanJoin", name, sock, data
    UserInChannel.connection.disconnect!
  end

  def handle_part name, sock, data
    data = data.split(' ')
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    userinchannel = UserInChannel.where("User = ? AND Channel = ?", data[0][1..-1], data[2])
    userinchannel.delete_all
    @e.Run "IRCChanPart", name, sock, data
    UserInChannel.connection.disconnect!
  end

  def handle_kick name, sock, data
    data = data.split(' ')
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    userinchannel = UserInChannel.where("User = ? AND Channel = ?", data[3], data[2])
    userinchannel.delete_all
    UserInChannel.connection.disconnect!
  end

  def handle_nick name, sock, data
    data = data.split(' ')
    User.establish_connection(@config["connections"]["databases"]["test"])
    nickd = User.sanitize data[2]
    nickuid = User.sanitize data[0][1..-1]
    User.connection.execute("UPDATE `users` SET `Nick` = #{nickd} WHERE `UID` = #{nickuid};")
    User.connection.disconnect!
  end

  def handle_chghost name, sock, data
    data = data.split(' ')
    User.establish_connection(@config["connections"]["databases"]["test"])
    chost = User.sanitize data[3]
    uid = User.sanitize data[2]
    User.connection.execute("UPDATE `users` SET `CHost` = #{chost} WHERE `UID` = #{uid};")
    User.connection.disconnect!
  end

  def handle_tmode name, sock, data
    data = data.split(' ')
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    nchan = UserInChannel.sanitize data[3]
    nmode = UserInChannel.sanitize data[4][1..-1]
    nuser = UserInChannel.sanitize data[5]

    UserInChannel.connection.execute("UPDATE `user_in_channels` SET `Modes` = CONCAT(`Modes`,#{nmode}) WHERE `User` = #{nuser} AND `Channel` = #{nchan};") if data[4].include?("+")

    if data[4].include?("-")
      modes = data[4][1..-1].split('')
      modes.each do |mode|
        user = UserInChannel.sanitize data[5]
        chan = UserInChannel.sanitize data[3]
        UserInChannel.connection.execute("UPDATE `user_in_channels` SET `Modes` = REPLACE(`Modes`,'#{mode}', '') WHERE `User` = #{user} AND `Channel` = #{chan};")
      end
    end
    UserInChannel.connection.disconnect!
  end

  def handle_mode name, sock, data
    modes = data.split(':')
    modes = modes[2]
    data = data.split(' ')

    User.establish_connection(@config["connections"]["databases"]["test"])
    nmode = User.sanitize modes[1..-1]
    uid = User.sanitize data[2]
    User.connection.execute("UPDATE `users` SET `UModes` = CONCAT(`UModes`,#{nmode}) WHERE `UID` = #{uid};") if modes.include?("+")

    if modes.include?("-")
      modes = modes[1..-1].split('')
      modes.each do |mode|
        User.connection.execute("UPDATE `users` SET `UModes` = REPLACE(`UModes`,'#{mode}', '') WHERE `UID` = #{uid};")
      end
    end
    User.connection.disconnect!
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @ircservers = []

    @config = c.Get

    User.establish_connection(@config["connections"]["databases"]["test"])
    Channel.establish_connection(@config["connections"]["databases"]["test"])
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])

    User.connection.execute("TRUNCATE `users`;")
    Channel.connection.execute("TRUNCATE `channels`;")
    UserInChannel.connection.execute("TRUNCATE `user_in_channels`;")

    User.connection.disconnect!
    Channel.connection.disconnect!
    UserInChannel.connection.disconnect!

    @e.on_event do |type, name, sock, data|
      if type == "IRCMsg"
        m = Regexp.new('.*?(\\d+)',Regexp::IGNORECASE);
        if m.match(data)
          handle_numeric name, sock, data, m.match(data)[1]
        end

        handle_chat    name, sock, data if data.include?(" PRIVMSG ") || data.include?(" NOTICE ")
        handle_ping    name, sock, data if data.include?(" PING ") || data.include?("PING ")
        handle_sid     name, sock, data if data.include?(" SID ")
        handle_euid    name, sock, data if data.include?(" EUID ")
        handle_sjoin   name, sock, data if data.include?(" SJOIN ")
        handle_quit    name, sock, data if data.include?(" QUIT ")
        handle_join    name, sock, data if data.include?(" JOIN ") and !data.include?(" SJOIN ")
        handle_part    name, sock, data if data.include?(" PART ")
        handle_tmode   name, sock, data if data.include?(" TMODE ")
        handle_chghost name, sock, data if data.include?(" CHGHOST ")
        handle_nick    name, sock, data if data.include?(" NICK ")
        handle_kick    name, sock, data if data.include?(" KICK ")
        handle_mode    name, sock, data if data.include?(" MODE ")
        handle_pass    name, sock, data if data.include?("PASS ") || data.include?(" PASS ")
        handle_server  name, sock, data if data.include?("SERVER ") || data.include?(" SERVER ")
      end
    end
  end
end
