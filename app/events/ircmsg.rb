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
    user.nick   = data[2] ? data[2] : ""
    user.ctime  = data[4] ? data[4] : ""
    user.umodes = data[5][1..-1] ? data[5][1..-1] : ""
    user.ident  = data[6] ? data[6] : ""
    user.chost  = data[7] ? data[7] : ""
    user.ip     = data[8] ? data[8] : ""
    user.uid    = data[9] ? data[9] : ""
    user.host   = data[10] ? data[10] : ""
    @ircservers.each do |hash|
      user.server = hash["server"] if data[0][1..-1] == hash["SID"]
      server = hash["server"]
    end

    user.server = "unknown.server" if user.server.nil?
    server = "unknown.server" if server.nil?
    user.nickserv = data[11]
    user.save
    User.connection.disconnect!

    @e.Run "EUID", data[2], server
  end

  def handle_sjoin name, sock, data
    users = data.split(':')[-1]
    data  = data.split(' ')

    return if data.count < 4
    return if data[4].nil?

    Channel.establish_connection(@config["connections"]["databases"]["test"])
    channel = Channel.new
    channel.ctime   = data[2]
    thechannel      = data[3]
    channel.channel = data[3]
    channel.modes   = data[4]
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
        userinchannel.channel = thechannel
        userinchannel.user = nickname
        userinchannel.modes = modes
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
    hash = {"SID" => data[-1][1..-1], "server" => "rpsuplink"}
    @ircservers.push(hash)
  end

  def handle_server name, sock, data
    server = data.split(' ')[1]
    @ircservers.collect { |hash|
      if hash["server"] == "rpsuplink"
        hash["server"] = server
      end
    }
  end

  def handle_squit name, sock, data
    server = data.split(' ')[1]
    sname = ""
    @ircservers.each { |s| sname = s["server"] if server == s["SID"] }
    @ircservers.delete_if { |s| sname == s["server"] }
    if sname.empty?
      puts "SENDTO_DEBUG UNKNOWN SERVER"
      return
    end
    User.establish_connection(@config["connections"]["databases"]["test"])
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    user = User.where(server: sname)
    user.each { |q|
      uc = UserInChannel.where(user: q[:uid])
      uc.delete_all
    }
    user.delete_all
    User.connection.disconnect!
    UserInChannel.connection.disconnect!
  end

  def handle_kill name, sock, data
    nick = data.split(' ')[2]

    User.establish_connection(@config["connections"]["databases"]["test"])
    user = User.where(uid: nick)
    user.delete_all

    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    channel = UserInChannel.where(user: nick)
    channel.delete_all
    User.connection.disconnect!
    UserInChannel.connection.disconnect!

    @e.Run "IRCClientQuit", name, sock, data
  end

  def handle_save name, sock, data
    uid = data.split(' ')[2]
    User.establish_connection(@config["connections"]["databases"]["test"])
    user = User.find_by(uid: uid)
    user.update(nick: uid)
    User.connection.disconnect!
  end

  def handle_tb name, sock, data
    data = data.split(' ')
    return if data[0] == 'CAPAB'
    return if data[1] == 'ENCAP'
    return if data.count < 4
    return if data[4].nil?
    topic = data[5..-1].join(' ')[1..-1]
    Channel.establish_connection(@config["connections"]["databases"]["test"])
    query = Channel.find_by(channel: data[2])
    query.update(topic: topic, topic_setat: data[3], topic_setby: data[4])
    Channel.connection.disconnect!
  end

  def handle_topic name, sock, data
    data = data.split(' ')
    User.establish_connection(@config["connections"]["databases"]["test"])
    Channel.establish_connection(@config["connections"]["databases"]["test"])

    topic = data[3..-1].join(' ')[1..-1]

    user = User.find_by(uid: data[0][1..-1])
    uobj = nil
    user.each { |info|
      User.connection.disconnect!
      uobj = info
    }

    if uobj.nil?
      setter = "unknown"
    else
      if uobj["CHost"] == '*'
        if uobj["Host"] == '*'
          uhost = uobj["IP"]
        else
          uhost = uobj["Host"]
        end
      else
        uhost = uobj["CHost"]
      end
      setter = "#{uobj["Nick"]}!#{uobj["Ident"]}@#{uhost}"
    end

    query = Channel.find_by(channel: data[2])
    query.update(topic: topic, topic_setat: Time.new.topic, topic_setby: setter)
    Channel.connection.disconnect!
  end

  def handle_quit name, sock, data
    data = data.split(' ')
    nick = data[0][1..-1]

    User.establish_connection(@config["connections"]["databases"]["test"])
    user = User.where(uid: nick)
    user.delete_all

    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    channel = UserInChannel.where(user: nick)
    channel.delete_all
    User.connection.disconnect!
    UserInChannel.connection.disconnect!

    @e.Run "IRCClientQuit", name, sock, data
  end

  def handle_join name, sock, data
    data = data.split(' ')
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    if data[2] == '0'
      userinchannel = UserInChannel.where(user: data[0][1..-1])
      userinchannel.delete_all
      @e.Run "IRCChanPart", name, sock, data
    else
      userinchannel = UserInChannel.new
      userinchannel.channel = data[3]
      userinchannel.user    = data[0][1..-1]
      userinchannel.modes   = ""
      userinchannel.save
      @e.Run "IRCChanJoin", name, sock, data
    end
    UserInChannel.connection.disconnect!
  end

  def handle_part name, sock, data
    data = data.split(' ')
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    userinchannel = UserInChannel.where(user: data[0][1..-1], channel: data[2])
    userinchannel.delete_all
    @e.Run "IRCChanPart", name, sock, data
    UserInChannel.connection.disconnect!
  end

  def handle_kick name, sock, data
    data = data.split(' ')
    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    userinchannel = UserInChannel.where(user: data[3], channel: data[2])
    userinchannel.delete_all
    UserInChannel.connection.disconnect!
  end

  def handle_nick name, sock, data
    data = data.split(' ')
    User.establish_connection(@config["connections"]["databases"]["test"])
    user = User.find_by(uid: data[0][1..-1])
    user.update(nick: data[2], ctime: data[3][1..-1])
    User.connection.disconnect!
  end

  def handle_chghost name, sock, data
    data = data.split(' ')
    User.establish_connection(@config["connections"]["databases"]["test"])
    user = User.find_by(uid: data[2])
    user.update(chost: data[3])
    User.connection.disconnect!
  end

  def handle_su name, sock, data
    data = data.split(' ')
    User.establish_connection(@config["connections"]["databases"]["test"])
    if data.count == 5
      uid  = data[4][1..-1]
      acct = '*'
    else
      uid  = data[4]
      acct = data[5][1..-1]
    end
    user = User.find_by(uid: uid)
    user.update(nickserv: acct)
    User.connection.disconnect!
  end

  def handle_certfp name, sock, data
    data = data.split(' ')
    User.establish_connection(@config["connections"]["databases"]["test"])
    user = User.find_by(uid: data[0][1..-1])
    user.update(certfp: data[4][1..-1])
    User.connection.disconnect!
  end

  def handle_tmode name, sock, data
    data = data.split(' ')

    UserInChannel.establish_connection(@config["connections"]["databases"]["test"])
    i = 5
    # Are we starting off with and addition or subtraction?
    addnow = data[4][0] == '+'

    # Go through each change
    data[4].split(//).each { |m|
      case m
      when '+'
        addnow = true
        next
      when '-'
        addnow = false
        next
      when 'f','j','k','l'
        i+=1 if addnow
        next
      when 'b','x','e','I'
        i+=1
        next
      end

      # Channel operator status changes
      if ['q','a','o','h','v'].include? m
        if addnow
          queryadd = UserInChannel.find_by(user: data[i], channel: data[3])
          if queryadd
            curmodes = queryadd[:modes] ? queryadd[:modes] : ''
            queryadd.update(modes: ('' + m).split(//).uniq.join)
          else
            queryadd = UserInChannel.new
            queryadd.channel = data[3]
            queryadd.user    = data[i]
            queryadd.modes   = m
            queryadd.save
          end
          i+=1
          next
        end

        if !addnow
          queryminus = UserInChannel.where(user: data[i], channel: data[3]).first
          curmodes = queryminus[:modes] ? queryminus[:modes] : ''
          newmode = curmodes.to_s.tr(m, '')
          queryminus.update(modes: newmode)
          i+=1
          next
        end
      end
    }
    UserInChannel.connection.disconnect!
  end

  def handle_mode name, sock, data
    modes = data.split(':')
    modes = modes[2]
    data = data.split(' ')

    User.establish_connection(@config["connections"]["databases"]["test"])
    uid = User.sanitize data[2]

    if modes.include? "+"
      modes = modes[1..-1]
      query = User.find_by(uid: data[2])
      query.update(umodes: (query.umodes + modes).split(//).uniq.sort.join)
    end

    if modes.include?("-")
      modes = modes[1..-1].split('')
      modes.each do |mode|
        query = User.where(uid: data[2]).first
        newmode = query[:umodes].to_s.tr(mode, '')
        query.update(umodes: newmode)
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

    User.destroy_all
    Channel.destroy_all
    UserInChannel.destroy_all

    User.connection.disconnect!
    Channel.connection.disconnect!
    UserInChannel.connection.disconnect!

    @e.on_event do |type, name, sock, data|
      if type == "IRCMsg"
        m = Regexp.new('.*?(\\d+)',Regexp::IGNORECASE);
        if m.match(data)
          handle_numeric name, sock, data, m.match(data)[1]
        end

        opt = data.upcase.split(' ')

        handle_pass    name, sock, data if opt[0] == "PASS"
        handle_server  name, sock, data if opt[0] == "SERVER"
        handle_ping    name, sock, data if opt[0] == "PING"
        handle_squit   name, sock, data if opt[0] == "SQUIT"
        #handle_kill    name, sock, data if opt[1] == "KILL" # Useless?
        #handle_save    name, sock, data if opt[1] == "SAVE" # Useless?
        handle_chat    name, sock, data if opt[1] == "PRIVMSG" or opt[1] == "NOTICE"
        handle_sid     name, sock, data if opt[1] == "SID"
        handle_euid    name, sock, data if opt[1] == "EUID"
        handle_sjoin   name, sock, data if opt[1] == "SJOIN"
        handle_quit    name, sock, data if opt[1] == "QUIT"
        handle_join    name, sock, data if opt[1] == "JOIN" and opt[1] != "SJOIN"
        handle_part    name, sock, data if opt[1] == "PART"
        handle_tmode   name, sock, data if opt[1] == "TMODE"
        handle_chghost name, sock, data if opt[1] == "CHGHOST"
        handle_nick    name, sock, data if opt[1] == "NICK"
        handle_kick    name, sock, data if opt[1] == "KICK"
        handle_mode    name, sock, data if opt[1] == "MODE"
        handle_tb      name, sock, data if opt[1] == "TB"
        handle_topic   name, sock, data if opt[1] == "TOPIC"
        handle_su      name, sock, data if opt[3] == "SU"
        handle_certfp  name, sock, data if opt[1] == "ENCAP" and opt[3] == "CERTFP"
      end
    end
  end
end
