require_relative '../libs/channel.rb'
require_relative '../libs/server.rb'
require_relative '../libs/user.rb'

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

  def handle_rping name, sock, line
    data        = line.split(' ')
    remote_sid  = data[0][1..-1]
    remote_name = data[2]
    our_sid     = data[3][1..-1]

    if our_sid == @params["sid"]
      send_data name, sock, ":#{our_sid} PONG #{@params["server_name"]} :#{remote_sid}\r\n"
    end
  end

  def handle_numeric name, sock, line, numeric
    hash = {"name" => name, "sock" => sock, "line" => line, "numeric" => numeric}
    @e.Run "IRCNumeric", hash
  end

  def handle_euid name, sock, data
    return if data.include?("ENCAP * GCAP :") or data.include?(" ENCAP ")
    data = data.split(' ')

    s = Server.find_by_sid data[0][1..-1]

    exists = UserStruct.find data[2]

    if exists
      @e.Run "RPSError", "Received EUID for an already existing nick #{data[2]}"
      return
    end

    u = UserStruct.new(s, data[9], data[2], data[6], data[7], data[10], data[8], data[4], data[5][1..-1], data[12..-1].join(' ')[1..-1])
    u.nickserv = data[11]
    u.modes = data[5].tr '+', ''
    s.usercount +=1

    @e.Run "EUID", data[2], s.sid
  end

  def handle_sjoin name, sock, data
    users = data.split(':')[-1]
    data  = data.split(' ')

    return if data.count < 4
    return if data[4].nil?

    c = ChannelStruct.find_by_name data[3]
    c ||= ChannelStruct.new data[3], data[2]

    offset = 0
    data[4].each_char do |c|
      offset += 1 if ['x','k','l','I','f','j','e','b','q','a''o','h','v'].include? c
    end

    parse_modestr c, data[4..(4+offset)]

    return if data[5 + offset] == nil or data[5 + offset] == ':'

    data[5 + offset..-1].each do |user|
      # First number is start of UID because of SID definition
      idx = 0
      pfx = ''
      user.each_char do |c|
        case c
        when '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
          break
        when '~', '&', '@', '%', '+'
          pfx += c
          idx +=1
        else
          idx += 1
        end
      end
      begin
        u = UserStruct.find_by_uid(user[idx..-1])
        c.add_user u
        u.join c

        if !pfx.empty?
          pfx.split(//).each { |p| c.add_access p, u }
        end

      rescue NoMethodError => e
        @e.Run "RPSError", "Error getting UID (#{user[(idx - 1)..-1]} for idx=#{idx} and user=#{user}): #{e.inspect}"
      end
    end
    @e.Run "IRCChanSJoin", name, sock, data
  end

  def handle_sid name, sock, data
    data = data.split(' ')
    s = Server.new data[4], data[2], data[5..-1].join(' ')[1..-1]
    s.time_connected = Time.now.to_i

    uplink = Server.find_by_sid data[0][1..-1]
    s.uplink = uplink
    @e.Run "ServerIntroduced", s, uplink
  end

  def handle_server2 name, sock, data
    data = data.split(' ')
    s = Server.new nil, data[2], data[4..-1].join(' ')[1..-1]
    s.time_connected = Time.now.to_i

    uplink = Server.find_by_name data[0][1..-1]
    s.uplink = uplink
    @e.Run "ServerIntroduced", s, uplink
  end

  def handle_pass name, sock, data
    data = data.split(' ')
    s = Server.new data[-1][1..-1], 'rpsuplink', ''
    s.time_connected = Time.now.to_i
  end

  def handle_server name, sock, data
    server = data.split(' ')[1]
    uplink = Server.find_by_name 'rpsuplink'
    if uplink
      client = Server.find_by_sid @params["sid"]
      uplink.name = server
      uplink.desc = data.split(' ')[3..-1].join(' ')[1..-1]
      client.uplink = uplink
      @e.Run "ServerIntroduced", client, uplink
    end
  end

  def handle_split split_server
    splits = Server.find_children split_server

    splits.each { |x|
      @e.Run "ServerSplit", x, UserStruct.user_count_by_server(x.sid)
      split_users = UserStruct.all_users_by_server x.sid
      if split_users.count > 0
        split_users.each { |user|
          user.channels.each { |c| c.del_user user }
          user.part_all
          user.server.usercount -= 1
          user.destroy if user
        }
      end
      x.destroy
    }
  end

  def handle_squit name, sock, data
    data = data.split(' ')
    split_sid = data[1]
    split_server = Server.find_by_sid split_sid

    if !split_server
      @e.Run "RPSError", "Received SQUIT for unknown SID #{split_sid}"
      return
    end

    handle_split split_server
  end

  def handle_kill name, sock, data
    nick = data.split(' ')[2]

    u = UserStruct.find nick
    u.channels.each { |c| c.del_user u }
    u.part_all
    u.server.usercount -= 1
    u.destroy if u
    @e.Run "IRCClientQuit", name, sock, data
  end

  def handle_save name, sock, data
    uid = data.split(' ')[2]
    u = UserStruct.find uid
    u.nick = uid
  end

  def handle_tb name, sock, data
    data = data.split(' ')
    return if data[0] == 'CAPAB'
    return if data[1] == 'ENCAP'
    return if data.count < 4
    return if data[4].nil?
    topic = data[5..-1].join(' ')[1..-1]

    c = ChannelStruct.find_by_name data[2]

    if !c
      @e.Run "RPSError", "Found TB for unknown channel #{data[3]}"
      return
    end

    c.topic_name   = topic
    c.topic_set_at = data[3]
    c.topic_set_by = data[4]
  end

  def handle_bmask name, sock, data
    data = data.split(' ')
    c = ChannelStruct.find_by_name data[3]

    if !c
      @e.Run "RPSError", "Found BMASK for unknown channel #{data[3]}"
      return
    end

    ts = data[2].to_i

    return if c.ts < ts
    return if !['b','e','x'].include? data[4]

    ban_list = data[5..-1].join(' ')[1..-1].split(' ')
    ban_list.each { |ban| c.add_ban ban, data[4] }
  end

  def handle_topic name, sock, data
    data = data.split(' ')

    topic = data[3..-1].join(' ')[1..-1]

    u = UserStruct.find_by_uid data[0][1..-1]
    c = ChannelStruct.find_by_name data[2]
    c.topic_name = topic
    c.topic_set_at = Time.new.to_i
    c.topic_set_by = u ? "#{u.nick}!#{u.ident}@#{u.chost}" : 'unknown'
  end

  def handle_quit name, sock, data
    data = data.split(' ')
    uid  = data[0][1..-1]

    u = UserStruct.find_by_uid uid
    u.channels.each { |c| c.del_user u }
    u.part_all
    u.server.usercount -= 1
    u.destroy if u

    @e.Run "IRCClientQuit", name, sock, data
  end

  def handle_join name, sock, data
    data = data.split(' ')

    u = UserStruct.find data[0][1..-1]

    if !u
      @e.Run "RPSError", "Received JOIN for unknown UID #{data[0][1..-1]}"
      return
    end

    if data[2] == '0'
      u.channels.each { |c| c.del_user u }
      u.part_all
    else
      c   = ChannelStruct.find_by_name data[3]
      c ||= ChannelStruct.new data[3], data[1]
      c.add_user u
      u.join c
    end
    @e.Run "IRCChanPart", name, sock, data
  end

  def handle_part name, sock, data
    data = data.split(' ')

    c = ChannelStruct.find_by_name data[2]
    u = UserStruct.find data[0][1..-1]
    c.del_user u
    u.part c

    @e.Run "IRCChanPart", name, sock, data
  end

  def handle_kick name, sock, data
    data = data.split(' ')

    c = ChannelStruct.find_by_name data[2]
    u = UserStruct.find data[3]
    c.del_user u
    u.part c
  end

  def handle_nick name, sock, data
    data = data.split(' ')

    u = UserStruct.find data[0][1..-1]

    if !u
      @e.Run "RPSError", "Received NICK for unknown UID #{data[0][1..-1]}"
      return
    end

    u.nick = data[2]
    u.ts   = data[3][1..-1].to_i
  end

  def handle_chghost name, sock, data
    data = data.split(' ')

    u = UserStruct.find_by_uid data[2]
    u.chost = data[3]
  end

  # Sometimes services can lag and log users
  # in after the user netsplits. It's rare but
  # it has happened. Found out the hard way.
  # Trust me.
  def handle_su name, sock, data
    data = data.split(' ')

    if data.count == 5
      u = UserStruct.find data[4][1..-1]
      return if !u
      u.nickserv = '*'
    else
      u = UserStruct.find data[4]
      return if !u
      u.nickserv = data[5][1..-1]
    end
  end

  def handle_certfp name, sock, data
    data = data.split(' ')

    u = UserStruct.find data[0][1..-1]
    u.certfp = data[4][1..-1]
  end

  def handle_tmode name, sock, data
    data = data.split(' ')

    c = ChannelStruct.find_by_name data[3]

    if !c
      @e.Run "RPSError", "Received TMODE for unknown channel #{data[3]}"
      return
    end

    return if data[2].to_i > c.ts

    parse_modestr c, data[4..-1]

    i = 5
    # Are we starting off with and addition or subtraction?
    addnow = data[4][0] == '+'

    # Go through each change
    data[4].split(//).each { |m|
      case m
      when '+' then addnow = true
      when '-' then addnow = false
      when 'f','j','k','l'
        i+=1 if addnow
      when 'b','x','e','I'
        i+=1
      # Channel operator status changes
      when 'q','a','o','h','v'
        u = UserStruct.find data[i]
        if addnow
          c.add_access m, u
        else
          c.del_access m, u
        end
        i+=1
      end
    }
  end

  def handle_mode name, sock, data
    modes = data.split(':')
    modes = modes[2]
    data  = data.split(' ')

    u = UserStruct.find data[0][1..-1]
    return if !u

    if modes.include? "+"

      if modes.include? 'o'
        u.isoper = true
      elsif modes.include? 'a'
        u.isadmin = true
      end

      structmodes = u.modes
      modes   = modes[1..-1]
      u.modes = (structmodes+modes).split(//).uniq.sort.join
    end

    if modes.include?("-")
      modes = modes[1..-1].split('')
      modes.each do |mode|
        structnewmode = u.modes.to_s.tr(mode, '')
        u.modes = structnewmode
      end
    end
  end

  def parse_modestr c, modes
    adding = nil
    if modes[0][0] == '+'
      adding = true
    elsif modes[0][0] == '-'
      adding = false
    end
    return if adding.nil?

    offset = 0

    modes[0].each_char do |char|
      case char
      when '+' then adding = true
      when '-' then adding = false
      when 'b', 'e', 'x'
        if adding
          c.add_ban modes[1 + offset], char
        else
          c.del_ban modes[1 + offset], char
        end
        offset += 1
      when 'k', 'l', 'I', 'f', 'j', 'q', 'a', 'o', 'h', 'v'
        offset += 1
      when 'P'
        if adding
          c.modes += char if !c.modes.include? char
        else
          c.modes.tr char, ''
        end
        c.set_permanent adding
        c.destroy if !adding && c.get_user_count == 0
      else
        if adding
          c.modes += char if !c.modes.include? char
        else
          c.modes.tr(char, '')
        end
      end
    end

    return nil
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = c.Get
    @params = @config["connections"]["clients"]["irc"]["parameters"]

    s = Server.new @params["sid"], @params["server_name"], @params["server_description"]
    s.time_connected = Time.now.to_i

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
        handle_bmask   name, sock, data if opt[1] == "BMASK"
        handle_server2 name, sock, data if opt[1] == "SERVER"
        handle_kill    name, sock, data if opt[1] == "KILL"
        handle_save    name, sock, data if opt[1] == "SAVE"
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
        handle_rping   name, sock, data if opt[1] == "PING"
      end
    end
  end
end
