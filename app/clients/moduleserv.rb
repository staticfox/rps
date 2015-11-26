require_relative "../libs/irc"

class ModuleServClient

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def connect_client
    idle_channels = []
    @config["idle"].each { |i| idle_channels << i["channel"] }
    @irc.add_client @parameters["sid"], "#{@client_sid}", "ModuleServ", "+ioS", "ModuleServ", "Serv1-Bot.GeeksIRC.net", "ModuleServ"
    idle_channels.each { |i|
       @irc.client_join_channel @client_sid, i
       @irc.client_set_mode @client_sid, "#{i} +o ModuleServ"
    }
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
    @config["control"].each { |c| control_channels << c["channel"] }

    @irc.privmsg @client_sid, target, get_stats if hash["command"] == "!status" and control_channels.include? target

    if hash["command"] == "!module" and control_channels.include? target
      cp = hash["parameters"].split(' ') if !hash["parameters"].nil?

      if cp.nil?
        cp = []
        cp.push("")
      end

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
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000001"
    @initialized = false

    @e.on_event do |type, name, sock|
      if type == "IRCClientInit"
        @config = @c.Get
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
          @initialized = true
          sleep 1
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end
  end
end
