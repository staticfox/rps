require_relative 'match.rb'

# Defines an IRC channel.
class ChannelStruct
  include Match

  @@channels = {}
  attr_reader :name, :ts, :bans, :exempts, :mutes
  attr_accessor :topic_name, :topic_set_at, :topic_set_by, :modes

  # Converts the given String to lowercase according to RFC1459 rules
  def self.to_lower s
    return s.downcase.tr '[]\\', '{}|'
  end

  # Creates a new channel.
  def initialize name, ts
    @name = ChannelStruct.to_lower name
    @ts = ts.to_i
    @users = []

    @permanent = false

    # ban and exempt entries are arrays themselves: [nick, ident, host]
    # If a sub-array only has one field, it's an extban on Chary at least
    @bans    = []
    @exempts = []
    @mutes   = []

    # modes
    @modes   = ''

    # access
    @owners  = []
    @admins  = []
    @ops     = []
    @halfops = []
    @voiced  = []

    # topic
    @topic_name = @topic_set_at = @topic_set_by = ''

    @@channels[@name] = self
  end

  def parse_ban mask
    i_idx = mask.index('!')
    h_idx = mask.index('@')

    extban = false
    if i_idx == nil || h_idx == nil
      if mask[0] == '$'
        extban = true
      else
        return false
      end
    end

    unless extban
      nick  = mask[0..(i_idx - 1)]
      ident = mask[(i_idx + 1)..(h_idx - 1)]
      host  = mask[(h_idx + 1)..-1]
    end

    return extban ? [mask] : [nick, ident, host]
  end

  def add_ban mask, type
    b = parse_ban mask

    if type == 'b'
      @bans.push << b
    elsif type == 'e'
      @exempts.push << b
    elsif type == 'x'
      @mutes.push << b
    end
  end

  def del_ban mask, type
    b = parse_ban mask

    if type == 'b'
      @bans.delete b
    elsif type == 'e'
      @exempts.delete b
    elsif type == 'x'
      @mutes.delete b
    end
  end

  def add_user user
    if user.is_a? UserStruct
      @users.push << user
    else
      @users.push << UserStruct.find(user)
    end
  end

  def is_user_in_channel user
    if user.is_a? UserStruct
      return @users.include? user
    else
      return @users.include? UserStruct.find user
    end
  end

  def is_owner user
    return @owners.include? user
  end

  def is_admin user
    return @admins.include? user
  end

  def is_op user
    return @ops.include? user
  end

  def is_halfop user
    return @halfops.include? user
  end

  def is_voice user
    return @voiced.include? user
  end

  def add_access level, user
    case level
    when '~'
      access = @owners
    when '&'
      access = @admins
    when '@'
      access = @ops
    when '%'
      access = @halfops
    when '+'
      access = @voiced
    end

    if user.is_a? UserStruct
      access << user
    else
      access << UserStruct.find(user)
    end
  end

  def del_access level, user
    case level
    when '~'
      access = @owners
    when '&'
      access = @admins
    when '@'
      access = @ops
    when '%'
      access = @halfops
    when '+'
      access = @voiced
    end


    if user.is_a? UserStruct
      access.delete user
    else
      access.delete(UserStruct.find(user))
    end
  end

  def del_user user
    if user.is_a? UserStruct
      @users.delete(user)
    else
      @users.delete(UserStruct.find(user))
    end
  end

  def destroy
    @users.clear
    @@channels.delete(ChannelStruct.to_lower(@name))
  end

  def get_user_count
    return @users.length
  end

  def get_users
    return @users
  end

  def set_permanent val
    @permanent = val
  end

  def is_permanent?
    return @permanent
  end

  def self.get_total_channels
    return @@channels.count
  end

  def self.find_by_name name
    return @@channels[ChannelStruct.to_lower(name)]
  end

  def self.check_extban u, extban
    if extban == '$a' && u.nickserv
      return true
    end

    if extban.start_with? '$a:'
      return true if Match.match(extban[3..-1], u.nickserv, true)
    end

    if extban.start_with? '$c:'
      u.channels.each do |chan|
        return ChannelStruct.to_lower(chan.name) == ChannelStruct.to_lower(extban[3..-1])
      end
    end

    if extban == '$o'
      return u.isoper
    end

    if extban.start_with? '$r:'
      return true if Match.match(extban[3..-1], u.gecos, true)
    end

    if extban.start_with? '$s:'
      return true if Match.match(extban[3..-1], u.server.name, true)
    end

    if extban.start_with? '$j:'
    end

    if extban.start_with? '$x:'
      return true if Match.match(extban[3..-1], "#{u.nick}!#{u.ident}@#{u.host}##{u.gecos}", true)
    end

    if extban == '$z'
    end

    return false
  end

  # TODO seperate extban look ups and make a flag between
  # mutes and ban searching
  def self.find_with_ban_against u
    # channel => ban
    @chans = {}
    @@channels.each do |name, c|
      isexempt = false
      c.exempts.each do |e|
        if e.length > 1
          # regular ban
          if Match.match(e[0], u.nick, true) && Match.match(e[1], u.ident, true) &&
            (Match.match(e[2], u.host, true) || Match.match(e[2], u.chost, true) || Match.match(e[2], u.ip, true))
            # Matches, he's exempt
            isexempt = true
            break
          end
        else
          # extban
          isexempt = ChannelStruct.check_extban(u, e[0])
        end
      end

      next if isexempt

      c.bans.each do |b|
        if b.length > 1
          # regular ban
          if Match.match(b[0], u.nick, true) && Match.match(b[1], u.ident, true) &&
            (Match.match(b[2], u.host, true) || Match.match(b[2], u.chost, true) || Match.match(b[2], u.ip, true))
            @chans[c] = b
            break
          end
        else
          if ChannelStruct.check_extban(u, b[0])
            @chans[c] = b
            break
          end
        end
      end
    end

    return @chans
  end

  def self.find_with_mute_against u
    # channel => ban
    @chans = {}
    @@channels.each do |name, c|
      isexempt = false
      c.exempts.each do |e|
        if e.length > 1
          # regular ban
          if Match.match(e[0], u.nick, true) && Match.match(e[1], u.ident, true) &&
            (Match.match(e[2], u.host, true) || Match.match(e[2], u.chost, true) || Match.match(e[2], u.ip, true))
            # Matches, he's exempt
            isexempt = true
            break
          end
        else
          # extban
          isexempt = ChannelStruct.check_extban(u, e[0])
        end
      end

      next if isexempt

      c.mutes.each do |b|
        if b.length > 1
          # regular ban
          if Match.match(b[0], u.nick, true) && Match.match(b[1], u.ident, true) &&
            (Match.match(b[2], u.host, true) || Match.match(b[2], u.chost, true) || Match.match(b[2], u.ip, true))
            @chans[c] = b
            break
          end
        else
          if ChannelStruct.check_extban(u, b[0])
            @chans[c] = b
            break
          end
        end
      end
    end

    return @chans
  end
end
