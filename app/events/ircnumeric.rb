require 'active_record'

class ConfigStuff < ActiveRecord::Base
end

class IRCNumeric

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
    @e.on_event do |type, hash|
      if type == "IRCNumeric"
        if hash["numeric"] == 376 || hash["numeric"] == "396"
          config = c.Get
          config = config["connections"]["clients"][hash["name"]]

          send_data hash["name"], hash["sock"], "PRIVMSG #{config["authserv"]} :#{config["authcommand"]} #{config["authname"]} #{config["authpass"]}" if !config["authserv"].nil? && !config["authcommand"].nil? && !config["authpass"].nil?

          sleep 2

          config["channels"].each do |channel|
            send_data hash["name"], hash["sock"], "JOIN #{channel}\r\nJOIN #{channel}\r\n"
            sleep 1
          end
        end

        config = c.Get

        ConfigStuff.establish_connection(config["connections"]["databases"]["test"])

        #record = ConfigStuff.first
        #puts "Number: #{record.Number} - Name: #{record.Name} - Value: #{record.Value}"

        #cs = ConfigStuff.new
        #cs.Number = 2
        #cs.Name = "Nick"
        #cs.Value = "th1"
        #cs.save
        #cs = nil

        #db = @d.GetConnection "test"
        #result = db.select_all("SELECT * FROM `Teams`")
        #result.each do |row|
        #  puts row
        #end
      end
    end
  end
end
