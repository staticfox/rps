#require_relative "socket-server"
require_relative "db"
require_relative "modules"
require_relative "conf"
require_relative "events"
require_relative "socket-client"

class Core

  c = Configuration.new
  e = Events.new
  d = DB.new e
  m = Modules.new e, c, d
  s = SocketClient.new e

  config = c.Get

  modules = config["modules"]

  modules.each do |classname, file|
    m.LoadByNameOfFile file, classname
  end

  clientsockets = config["connections"]["clients"]
  databasesockets = config["connections"]["databases"]

  databasesockets.each do |hash|
    name = nil
    hash.each do |k|
      name = k.to_s if name.nil?
      hash = k
    end
    puts "Database Connection Found - Name: #{name} - Hash: #{hash}"
    puts "Creating Database Connection - #{name}"
    d.Create name, hash
  end

  clientsockets.each do |hash|
    name = nil
    hash.each do |k|
      name = k.to_s if name.nil?
      hash = k
    end
    puts "Client Socket Found - Name: #{name} - Hash: #{hash}"
    puts "Creating Client Socket - #{name}"
    s.Create name, hash["host"], hash["port"], hash["ssl"]
  end

  loop {
    begin
      s.CheckForNewData
      sleep 0.001
    rescue Exception => ex
      e.Run "Error", ex
      msg = "Exiting due to #{ex.class == Interrupt ? "interrupt signal" : "exception"}"
      e.Run "Shutdown", msg
      sleep 0.2
      e.Run "Disconnect", msg
      exit
    end
  }

end # End Class "Core"
