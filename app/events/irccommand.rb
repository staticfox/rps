class IRCCommand

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def send_chat type, target, string, name, sock
    send_data name, sock, "#{type} #{target} :#{string}\r\n"
  end

  def handle_privmsg hash
    target = hash["target"]
    target = hash["nickname"] if !hash["target"].include?("#")

    if hash["command"] == "!help"
      target = hash["target"]
      target = hash["nickname"] if !hash["target"].include?("#")
      send_chat "PRIVMSG", target, "No help can be given. Sorry!", hash["name"], hash["sock"]
    end

  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d
    @e.on_event do |type, hash|
      if type == "IRCChat"
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end
  end
end
