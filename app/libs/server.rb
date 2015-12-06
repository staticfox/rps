# Defines and describes a server.
class Server
  attr_accessor :usercount, :name, :desc, :uplink, :time_connected
  attr_reader :sid

  @@servers = {}
  @@servers_by_name = {}

  def initialize sid, name, desc
    @sid = sid
    @name = name
    @desc = desc

    @usercount = 0

    @@servers[@sid] = self
    @@servers_by_name[@name] = self

    # Uplink
    @uplink = nil

    # Time connected
    @time_connected = 0

    @split = false
  end

  def destroy
    @@servers.delete(@sid)
  end

  def self.find_children split
    split_array = []
    split_array.push(split)
    @@servers.each do |key, value|
      if value.uplink and value.uplink.sid == split.sid
        split_array.push(value)
      end
    end

    while !get_recursion(split_array).empty?
      get_recursion(split_array).each { |x| split_array << x }
    end

    return split_array
  end

  def self.get_recursion children
    deeper_split = []
    @@servers.each do |key, value|
      if value.uplink and !children.include? value
        children.each do |c|
          if c.name == value.uplink.name
            deeper_split << value
          end
        end
      end
    end
    return deeper_split
  end

  def self.servers_count
    return @@servers.count
  end

  def self.find_by_sid sid
    return @@servers[sid]
  end

  def self.find_by_name name
    return @@servers_by_name[name]
  end

  def self.all
    return @@servers.values
  end
end
