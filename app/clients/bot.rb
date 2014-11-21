require_relative "../libs/irc"

class BotClient

	def send_data name, sock, string
                time = Time.now
                puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
                sock.send string, 0
        end

	def connect_client
		@irc.add_client @parameters["sid"], "#{@client_sid}", "Bot", "+ioS", "Bot", "GeeksIRC.net", "Bot"
	end

	def handle_privmsg hash
		@e.Run "Bot-Chat", hash
		target = hash["target"]
		target = hash["from"] if hash["target"] == @client_sid
		@irc.privmsg @client_sid, target, "This is only a test." if hash["command"] == "!test"
	        #@irc.privmsg @client_sid, "Ryan", "#{hash['from']} is an oper." if @irc.is_oper_uid hash["from"]
	end

	def init e, m, c, d
                @e = e
                @m = m
                @c = c
                @d = d

		config = c.Get
		@parameters = config["connections"]["clients"]["irc"]["parameters"]
		@client_sid = "#{@parameters["sid"]}000003"
		@initialized = false

		@e.on_event do |type, name, sock|
			if type == "IRCClientInit" then
				config = @c.Get
                                @irc = IRCLib.new name, sock, config["connections"]["databases"]["test"]
                                connect_client
				@e.Run "LimitServ-Init", name, sock
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
