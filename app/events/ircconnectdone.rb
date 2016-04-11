class IRCConnectDone

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send "#{string}\r\n", 0
  end

  def init e, m, c, d
    @e = e
    @c = c
    @d = d

    @e.on_event do |type, name, sock, data|
      if type == "ConnectionCompleted"
        config = c.Get
        parameters = config["connections"]["clients"]["irc"]["parameters"]
        sid = parameters["sid"]
        password = parameters["server_password"]
        name = parameters["server_name"]
        description = parameters["server_description"]
        time = Time.now.to_i
        send_data name, sock, "PASS #{password} TS 6 #{sid}"
        send_data name, sock, "CAPAB :QS EX CHW IE KLN KNOCK ZIP TB UNKLN CLUSTER ENCAP SERVICES RSFNC SAVE EUID EOPMOD BAN MLOCK"
        send_data name, sock, "SERVER #{name} 1 :#{description}"
        send_data name, sock, "SVINFO 6 6 0 #{time}"
        sleep 0.5
        e.Run "IRCClientInit", name, sock
      end
    end
  end
end
