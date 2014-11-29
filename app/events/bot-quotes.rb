require "active_record"

require_relative "../libs/irc"

class Quote < ActiveRecord::Base
end

class BotQuotes

	def send_data name, sock, string
                time = Time.now
                puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
                sock.send string, 0
        end

	def handle_privmsg hash
		target = hash["target"]
		target = hash["from"] if hash["target"] == @client_sid
		@irc.privmsg @client_sid, target, "This is only a test." if hash["command"].downcase == "!test"
	        #@irc.privmsg @client_sid, "Ryan", "#{hash['from']} is an oper." if @irc.is_oper_uid hash["from"]

		if hash["command"].downcase == "!q" and target.include?("#") then
                        cp = hash["parameters"].split(' ') if !hash["parameters"].nil?

			if cp.nil? then
				cp = []
				cp.push("")
			end

                        if cp[0].downcase == "add" then
				(@irc.privmsg @client_sid, target, "You need to be a halfop or higher to add quotes into the database."; return) if !@irc.is_chan_founder(target, hash["from"]) and !@irc.is_chan_admin(target, hash["from"]) and !@irc.is_chan_op(target, hash["from"]) and !@irc.is_chan_halfop(target, hash["from"])
				Quote.establish_connection(@config["connections"]["databases"]["test"])
				quote = Quote.new
				quote.Channel = target
				quote.Person = @irc.get_nick_from_uid(hash["from"])
				quote.Quote = hash["parameters"][4..-1]
				quote.Time = Time.now.to_i - 18000
				quote.save
				Quote.connection.disconnect!
				@irc.privmsg @client_sid, target, "Quote Saved!"
                        end

                        if cp[0].downcase == "del" then
				(@irc.privmsg @client_sid, target, "You need to be a founder remove quotes from the database."; return) if !@irc.is_chan_founder(target, hash["from"])
				Quote.establish_connection(@config["connections"]["databases"]["test"])
				query = Quote.where('ID = ? AND Channel = ?', cp[1], target)

				if query.size == 0 then
					@irc.privmsg @client_sid, target, "Quote ID #{cp[1]} does not exist for #{target}."
					Quote.connection.disconnect!
					return
				end

				query.delete_all
				@irc.privmsg @client_sid, target, "Deleted quote ID ##{cp[1]}."
				Quote.connection.disconnect!				
                        end

			if cp[0].downcase == "search" then
				Quote.establish_connection(@config["connections"]["databases"]["test"])
                                query = Quote.where('Channel = ? AND Quote LIKE ?', target, "%#{cp[1]}%")

				if query.size == 0 then
                                        @irc.privmsg @client_sid, target, "No quotes could be found for #{target}."
                                        Quote.connection.disconnect!
                                        return
                                end

				Thread.new do
				query.each do |row|
					time = Time.at(row.Time.to_i).strftime("%m/%d/%y @ %-l:%M %p Eastern")
					@irc.privmsg @client_sid, target, "ID: ##{row.ID} - Submitted By: #{row.Person} - #{time} - #{row.Quote}"
					sleep 0.4
				end
				Quote.connection.disconnect!
				end
			end

			if cp[0] == "" then
				Quote.establish_connection(@config["connections"]["databases"]["test"])
                                query = Quote.where('Channel = ?', target).order("RAND()").first

				#puts query.methods

				#if query.size == 0 then
                                #        @irc.privmsg @client_sid, target, "No quotes could be found for #{target}."
                                #        Quote.connection.disconnect!
                                #        return
                                #end
				
				return if query.nil? or query.Time.nil?

				time = Time.at(query.Time.to_i).strftime("%m/%d/%y @ %-l:%M %p Eastern")
                                @irc.privmsg @client_sid, target, "ID: ##{query.ID} - Submitted By: #{query.Person} - #{time} - #{query.Quote}"
				Quote.connection.disconnect!
			end

                        #@irc.privmsg @client_sid, target, "Received the !q command with these parameters. #{cp}"
                end

	end

	def init e, m, c, d
                @e = e
                @m = m
                @c = c
                @d = d

		@config = c.Get
		parameters = @config["connections"]["clients"]["irc"]["parameters"]
		@client_sid = "#{parameters["sid"]}000003"
		@initialized = false

		Quote.establish_connection(@config["connections"]["databases"]["test"])
		Quote.connection.disconnect!

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
