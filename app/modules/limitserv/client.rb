require_relative "../../libs/irc"

class LimitServClient

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def connect_client
    @irc.add_client @parameters["sid"], "#{@client_sid}", "LimitServ", "+ioS", "Services", "GeeksIRC.net", "LimitServ"
  end

  def shutdown message
    @irc.remove_client @client_sid, message
  end

  def handle_privmsg hash
    @e.Run "LimitServ-Chat", hash
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    config = c.Get
    @parameters = config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000002"
    @initialized = false

    @e.on_event do |type, name, sock|
      if type == "IRCClientInit"
        config = @c.Get
        @irc = IRCLib.new name, sock, config["connections"]["databases"]["test"]
        connect_client
        @e.Run "LimitServ-Init", name, sock
        @initialized = true
      end
    end

    @e.on_event do |type, hash|
      if type == "IRCChat"
        if !@initialized
          config = @c.Get
          @irc = IRCLib.new hash["name"], hash["sock"], config["connections"]["databases"]["test"]
          connect_client
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
