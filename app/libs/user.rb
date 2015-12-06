class UserStruct
  @@users_by_uid = {}
  @@users_by_nick = {}

  attr_reader :uid, :host, :ip, :channels, :server
  attr_accessor :ident, :chost, :isoper, :isadmin, :olevel, :certfp, :nickserv, :ts, :gecos, :modes

  def initialize server, uid, nick, ident, chost, host, ip, ts, umodestr, gecos
    @isoper = umodestr.include?('o')
    @isadmin = umodestr.include?('a')
    @olevel = if @isadmin
                "admin"
              elsif @isoper
                "oper"
              else
                nil
              end
    @uid    = uid
    @nick   = nick
    @ident  = ident
    @chost  = chost
    @host   = host == '*' ? ip : host # i.e., no real host
    @ip     = ip == 0 ? chost : ip
    @ts     = ts.to_i
    @gecos  = gecos
    @certfp = nil
    @nickserv     = nil
    @channels = []
    @server = server
    @modes = ''

    @@users_by_uid[@uid] = self
    @@users_by_nick[ChannelStruct.to_lower(@nick)] = self
  end

  def join channel
    if channel.is_a? ChannelStruct
      @channels << channel
    else
      @channels << ChannelStruct.find(channel)
    end
  end

  def part channel
    if channel.is_a? ChannelStruct
      @channels.delete(channel)
    else
      @channels.delete(ChannelStruct.find(channel))
    end
  end

  def destroy
    @@users_by_uid.delete(@uid)
    @@users_by_nick.delete(ChannelStruct.to_lower(@nick))
    part_all
  end

  def part_all
    @channels.clear
  end

  def nick
    return @nick
  end

  def nick= nick
    @@users_by_nick.delete(ChannelStruct.to_lower(@nick))
    @nick = nick
    @@users_by_nick[ChannelStruct.to_lower(@nick)] = self
  end

  def self.get_total_users
    return @@users_by_uid.count
  end

  def self.get_oper_count
    i = 0
    @@users_by_uid.each do |key, value|
      i+=1 if value.isoper and !value.modes.include? 'S'
    end
    return i
  end

  def self.get_services_count
    i = 0
    @@users_by_uid.each do |key, value|
      i+=1 if value.modes.include? 'S'
    end
    return i
  end

  def self.find_by_uid uid
    return @@users_by_uid[uid]
  end

  def self.find_by_nick nick
    return @@users_by_nick[ChannelStruct.to_lower(nick)]
  end

  def self.find target
    u = @@users_by_uid[target]
    if u == nil
      return @@users_by_nick[ChannelStruct.to_lower(target)]
    else
      return u
    end
  end

  def self.all
    return @@users_by_uid.values
  end

  def self.all_users_by_server sid
    objects = []
    @@users_by_uid.each do |key, value|
      objects << value if value.server.sid == sid
    end
    return objects
  end

  # FIXME
  def self.user_count_by_server sid
    i = 0
    @@users_by_uid.each do |key, value|
      i+=1 if value.server.sid == sid
    end
    return i
  end
end
