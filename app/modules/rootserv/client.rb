require_relative "../../libs/irc"

class RootservClient

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def connect_client
    joined = []
    @irc.add_client @parameters["sid"], @client_sid, @parameters["server_name"], @rs["nick"], @rs["modes"], @rs["user"], @rs["host"], @rs["real"]
    @rs["idle_channels"].split(',').each { |i|
      next if joined.include? i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@rs["nick"]}"
    }
    @rs["control_channels"].split(',').each { |i|
      next if joined.include? i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@rs["nick"]}"
    }
    if @rs["debug_channels"]
      @rs["debug_channels"].split(',').each { |i|
        next if joined.include? i; joined << i
        @irc.client_join_channel @client_sid, i
        @irc.client_set_mode @client_sid, "#{i} +o #{@rs["nick"]}"
      }
    end
  end

  def shutdown message
    @irc.remove_client @client_sid, message
  end

  def sendto_debug message
    @rs["control_channels"].split(',').each { |x| @irc.privmsg @client_sid, x, message } if @rs["control_channels"]
  end

  def sendto_not_so_important_debug message
    @rs["debug_channels"].split(',').each { |x| @irc.privmsg @client_sid, x, message } if @rs["debug_channels"]
  end

  def announce_new_server client, hub
    sendto_not_so_important_debug "#{client.name}[#{client.sid ? client.sid : "Juped"}] introduced by #{hub.name}[#{hub.sid}]"
  end

  def announce_split_server server, count
    sendto_not_so_important_debug "#{server.name} split from #{server.uplink.name} - #{count} user#{count == 1 ? '' : 's'} lost"
  end

  def handle_privmsg hash
    target = hash["target"]
    target = hash["from"] if target == @client_sid

    return if hash["target"] != @client_sid
    return if ['#', '&'].include? target[0]

    if @irc.is_oper_uid target
      return @e.Run "Rootserv-Chat", hash
    else
      return sendto_debug "Denied access to #{@irc.get_nick_from_uid hash["from"]} (non-oper) [#{hash["command"]} #{hash["parameters"]}]"
    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = @c.Get
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000004"
    @initialized = false

    @e.on_event do |type, name, sock|
      if type == "IRCClientInit"
        @config = @c.Get
        @rs = @config["rootserv"]
        @irc = IRCLib.new name, sock, @config["connections"]["databases"]["test"]
        connect_client
        @initialized = true
      end
    end

    @e.on_event do |type, nick, server|
      if type == "EUID"
        @irc.collide nick, server
      end
    end

    @e.on_event do |type, hash|
      if type == "IRCChat"
        if !@initialized
          @config = @c.Get
          @irc = IRCLib.new hash["name"], hash["sock"], @config["connections"]["databases"]["test"]
          connect_client
          sleep 1
          join_channels
          @initialized = true
          sleep 1
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end

    @e.on_event do |signal, param|
      shutdown param if signal == "Shutdown"
    end

    @e.on_event do |event, client, hub|
      announce_new_server client, hub if event == "ServerIntroduced"
    end

    @e.on_event do |event, server, count|
      announce_split_server server, count if event == "ServerSplit"
    end

    @e.on_event do |event, message|
      sendto_debug message if event == "DebugRootServ"
    end
  end
end
