require_relative "../libs/irc"

class BotClient

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def handle_privmsg hash
    target = hash["target"]
    target = hash["from"] if target == @client_sid
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    config = @c.Get
    @parameters = config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000003"
    @initialized = false

    @e.on_event do |type, hash|
    if type == "Bot-Chat"
      if !@initialized
        config = @c.Get
        @irc = IRCLib.new hash["name"], hash["sock"], config["connections"]["databases"]["test"]
        @initialized = true
      end
      handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end
  end
end
