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
  end

  def shutdown message
    @irc.remove_client @client_sid, message
  end

  def sendto_debug message
    @rs["debug_channels"].split(',').each { |x| @irc.privmsg @client_sid, x, message } if @rs["debug_channels"]
    @rs["control_channels"].split(',').each { |x| @irc.privmsg @client_sid, x, message }
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

  end
end
