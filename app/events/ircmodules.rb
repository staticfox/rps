class IRCModules

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

    if hash["command"] == "!module"
      cp = hash["parameters"].split(' ')
      if cp[0] == "load"
        if !File.file?(cp[1]) || !cp[1].include?(".rb")
          send_chat "PRIVMSG", target, "[MODULE ERROR] Could not find file: #{cp[1]}", hash["name"], hash["sock"]
          return
        end

        result = @m.LoadByNameOfFile cp[1], cp[2]

        send_chat "PRIVMSG", target, "[MODULE ERROR] Could not load file: #{cp[1]}", hash["name"], hash["sock"] if !result
        send_chat "PRIVMSG", target, "[MODULE] Loaded file '#{cp[1]}' with class '#{cp[2]}'", hash["name"], hash["sock"] if result
      end

      if cp[0] == "unload"
        result = @m.UnloadByClassName cp[1]
        send_chat "PRIVMSG", target, "[MODULE ERROR] Could not unload module: #{cp[1]} - Not loaded? Wrong module name?", hash["name"], hash["sock"] if !result
        send_chat "PRIVMSG", target, "[MODULE] Successfully unloaded #{cp[1]}", hash["name"], hash["sock"] if result
      end

      send_chat "PRIVMSG", target, "Received the !module command with these parameters. #{cp}", hash["name"], hash["sock"]
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
