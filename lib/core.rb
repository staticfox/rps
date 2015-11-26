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
    rescue Exception => e
      if m.GetModuleByClassName("ModuleServClient")
        m.GetModuleByClassName("ModuleServClient").sendto_debug e.message
        m.GetModuleByClassName("ModuleServClient").sendto_debug e.backtrace
        m.GetModuleByClassName("ModuleServClient").wallop_problem "\x02SHUTTING DOWN DUE TO EXCEPTION\x02: #{e.message}"
      end
      if m.GetModuleByClassName("LimitServCore")
        m.GetModuleByClassName("LimitServCore")._internal_nuke
      end
      exit
    end
  }

end # End Class "Core"
