require_relative "../libs/irc"

class ModuleServClient

    def send_data name, sock, string
        time = Time.now
        puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
        sock.send string, 0
    end

    def connect_client
        @irc.add_client @parameters["sid"], "#{@client_sid}", "ModuleServ", "+ioS", "ModuleServ", "Serv1-Bot.GeeksIRC.net", "ModuleServ"
        sleep 1
        @irc.client_join_channel @client_sid, "#care"
        @irc.client_join_channel @client_sid, "#services"
        @irc.client_join_channel @client_sid, "#debug"
        sleep 1
        @irc.client_set_mode @client_sid, "#care +o ModuleServ"
        @irc.client_set_mode @client_sid, "#services +o ModuleServ"
        @irc.client_set_mode @client_sid, "#debug +o ModuleServ"
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
        target = hash["from"] if hash["target"] == @client_sid
        @irc.privmsg @client_sid, target, "Test" if hash["command"] == "!test" and hash["target"] == "#debug"

        #@irc.privmsg @client_sid, target, "#{hash["from"]}: I see you're not away." if hash["command"] == "!notafk"

        @irc.privmsg @client_sid, target, get_stats if hash["command"] == "!status" and hash["target"] == "#debug"

        if hash["command"] == "!module" and hash["target"] == "#debug" then
            cp = hash["parameters"].split(' ') if !hash["parameters"].nil?

            if cp.nil? then
                cp = []
                cp.push("")
            end

                if cp[0] == "load"
                    if !File.file?(cp[1]) || !cp[1].include?(".rb") then
                        @irc.privmsg @client_sid, target, "[MODULE ERROR] Could not find file: #{cp[1]}"
                        return
                    end

                    result = @m.LoadByNameOfFile cp[1], cp[2]

                    @irc.privmsg @client_sid, target, "[MODULE ERROR] Could not load file: #{cp[1]}" if !result
                    @irc.privmsg @client_sid, target, "[MODULE] Loaded file '#{cp[1]}' with class '#{cp[2]}'" if result
                end

                if cp[0] == "unload" then
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

        config = c.Get
        @parameters = config["connections"]["clients"]["irc"]["parameters"]
        @client_sid = "#{@parameters["sid"]}000001"
        @initialized = false

        @e.on_event do |type, name, sock|
            if type == "IRCClientInit" then
                config = @c.Get
                @irc = IRCLib.new name, sock, config["connections"]["databases"]["test"]
                connect_client
                @initialized = true
            end
        end

        @e.on_event do |type, hash|
            if type == "IRCChat" then
                if !@initialized then
                    config = @c.Get
                    @irc = IRCLib.new hash["name"], hash["sock"], config["connections"]["databases"]["test"]
                    connect_client
                    @initialized = true
                    sleep 1
                end
                handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
            end
        end
    end
end