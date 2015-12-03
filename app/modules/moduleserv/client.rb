require_relative "../../libs/irc"

class ModuleServClient

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def connect_client
    joined = []
    @irc.add_client @parameters["sid"], @client_sid, @parameters["server_name"], @ms["nick"], @ms["modes"], @ms["user"], @ms["host"], @ms["real"]
    @ms["idle_channels"].split(',').each { |i|
      next if joined.include? i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@ms["nick"]}"
    }
    @ms["debug_channels"].split(',').each { |i|
      next if joined.include? i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@ms["nick"]}"
    }
    @ms["control_channels"].split(',').each { |i|
      next if joined.include? i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@ms["nick"]}"
    }
  end

  def sendto_debug message
    @ms["debug_channels"].split(',').each { |i|
       @irc.privmsg @client_sid, i, message
    }
  end

  def wallop_problem message
    @irc.wallop @client_sid, message
  end

  def handle_exception param
    if param.class == Interrupt
      sendto_debug "Received interrupt signal, shutting down"
      wallop_problem "\x02Shutting down due to interrupt signal\x02"
    else
      sendto_debug param.message
      sendto_debug param.backtrace
      wallop_problem "\x02Shutting down due to exception\x02: #{param.message}"
    end
  end

  def shutdown message
    @irc.remove_client @client_sid, message
  end

   def get_stats
    GC.start
    num = `cat /proc/#{Process.pid}/status | grep "Threads"`.strip
    num = num.split("\t")

    ram = `cat /proc/#{Process.pid}/status | grep "VmSize"`.strip
    ram = ram.split("\t")
    return "[STATUS] Currently using #{num[1]} threads and #{ram[1][0..-3].to_i/1024} MB of memory."
  end

  def handle_privmsg hash
    target = hash["target"]
    target = hash["from"] if target == @client_sid

    control_channels = []
    @ms["control_channels"].split(',').each { |c| control_channels << c }

    @irc.privmsg @client_sid, target, get_stats if hash["command"] == "!status" and control_channels.include? target

    if hash["command"] == "!module" and control_channels.include? target
      cp = hash["parameters"].split(' ')
      cp = [""] if cp.empty?

      if cp[0] == "load"
        if !File.file?(cp[1]) || !cp[1].include?(".rb")
          @irc.privmsg @client_sid, target, "[MODULE ERROR] Could not find file: #{cp[1]}"
          return
        end

        result = @m.LoadByNameOfFile cp[1], cp[2]

        @irc.privmsg @client_sid, target, "[MODULE ERROR] Could not load file: #{cp[1]}" if !result
        @irc.privmsg @client_sid, target, "[MODULE] Loaded file '#{cp[1]}' with class '#{cp[2]}'" if result
      end

      if cp[0] == "unload"
        result = @m.UnloadByClassName cp[1]
        @irc.privmsg @client_sid, target, "[MODULE ERROR] Could not unload module: #{cp[1]} - Not loaded? Wrong module name?" if !result
        @irc.privmsg @client_sid, target, "[MODULE] Successfully unloaded #{cp[1]}" if result
      end
      @irc.privmsg @client_sid, target, "Received the !module command with these parameters. #{cp}"
    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = c.Get
    @ms = @config["moduleserv"]
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000001"
    @initialized = false

    @e.on_event do |type, name, sock|
      if type == "IRCClientInit"
        @config = @c.Get
        @ms = @config["moduleserv"]
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
          @ms = @config["moduleserv"]
          @irc = IRCLib.new hash["name"], hash["sock"], @config["connections"]["databases"]["test"]
          connect_client
          @initialized = true
          sleep 1
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end

    @e.on_event do |signal, param|
      case signal
      when "Shutdown" # param is a string
        shutdown param
      when "Error" # param is an exception
        handle_exception param
      when "Disconnect"
        # FIXME Move this out of ModuleServ and in to a connection manager with
        # an IRCLib
        @irc.squit @parameters["server_name"], param
      end
    end

  end
end
