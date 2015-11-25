class NewData

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d
    @e.on_event do |type, name, sock, data|
      if type == "NewData"
        @e.Run "IRCMsg", name, sock, data
      end
    end
  end
end
