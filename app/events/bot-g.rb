require "mechanize"
require "google-search"

require_relative "../libs/irc"

class BotG

	def send_data name, sock, string
                time = Time.now
                puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
                sock.send string, 0
        end

	def gc parameters
		doc = Mechanize.new.get("http://www.google.com/search?q=#{parameters}")
		result = doc.search("//h2[@class='r']").inner_text
		return "No Result Found." if result == ""
		return result
	end

	def gs parameters
		data = Google::Search::Web.new(:query => parameters)
		array = []

		data.each do |result|
        		array.push(result)
		end
		
		return "#{array[0].title} - #{array[0].uri}" if !array[0].nil?
		return "No Result Found."
	end

	def handle_privmsg hash
		@e.Run "Bot-Chat", hash
		target = hash["target"]
		target = hash["from"] if hash["target"] == @client_sid
		@irc.privmsg @client_sid, target, "This is only a test." if hash["command"] == "!test"

		@irc.privmsg @client_sid, target, "Google Calculator: #{gc(hash["parameters"])}" if hash["command"] == "!gc"
		@irc.privmsg @client_sid, target, "Google Search: #{gs(hash["parameters"])}" if hash["command"] == "!gs"

	        #@irc.privmsg @client_sid, "Ryan", "#{hash['from']} is an oper." if @irc.is_oper_uid hash["from"]
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
                        if type == "Bot-Chat" then
				if !@initialized then
					config = @c.Get
					@irc = IRCLib.new hash["name"], hash["sock"], config["connections"]["databases"]["test"]
					@initialized = true
				end				
                                handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
                        end
                end
        end

end
