require_relative '../libs/channel.rb'
require_relative '../libs/server.rb'
require_relative '../libs/user.rb'

class IRCLib

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def add_client server_sid, uid, server, nick, modes, user, host, real
    @bots.each { |bot| return -1 if bot["nick"] == nick }

    s = Server.find_by_sid server_sid
    u = UserStruct.new(s, uid, nick, user, host, host, 0, Time.now.to_i, modes.tr('+', ''), "TODO")
    u.nickserv = '*'
    u.modes = modes.tr '+', ''
    s.usercount +=1

    send_data @name, @sock, ":#{server_sid} EUID #{nick} 2 #{Time.now.to_i} #{modes} #{user} #{host} 0 #{uid} * * :#{real}\r\n"

    hash = {"name" => @name, "sock" => @sock, "nick" => nick, "user" => user, "host" => host, "uid" => uid, "server" => server, "server_sid" => server_sid, "real" => real, "modes" => modes}
    @bots.push(hash)
  end

  def remove_client uid, msg = nil
    @bots.each { |bot|
      u = UserStruct.find_by_uid bot["uid"]
      u.server.usercount -= 1
      u.destroy if u
      send_data @name, @sock, ":#{uid} QUIT :#{msg}\r\n" if bot["uid"] == uid
      @bots.delete bot if bot["uid"] == uid
    }
    return -1
  end

  def collide nick, server
    u = UserStruct.find nick
    return if !u

    @bots.each { |bot|
      if bot["nick"].downcase == u.nick.downcase
        if bot["server"].downcase != u.server.name.downcase
          server_kill bot["server_sid"], u.uid, bot["server"], "Nick collision with services (new)"
          nick bot["uid"], bot["nick"]
        end
      end
    }

  end

  def server_set_mode server_sid, string
    ts = Time.now.to_i
    send_data @name, @sock, ":#{server_sid} TMODE #{ts} #{string}\r\n"
  end

  def client_set_mode uid, string
    send_data @name, @sock, ":#{uid} MODE #{string}\r\n"
  end

  def client_join_channel uid, channel
    ts = Time.now.to_i

    u = UserStruct.find uid
    return if !u
    c = ChannelStruct.find_by_name channel
    c ||= ChannelStruct.new channel, ts
    c.add_user u
    c.add_access '@', u
    u.join c

    send_data @name, @sock, ":#{uid} JOIN #{ts} #{channel} +\r\n"
  end

  def is_user_in_channel uid, channel
    c = ChannelStruct.find_by_name channel
    u = UserStruct.find uid
    return false if !c
    return false if !u
    return c.is_user_in_channel u
  end

  def client_part_channel uid, channel, reason = ""
    send_data @name, @sock, ":#{uid} PART #{channel} :#{reason}\r\n"
    c = ChannelStruct.find_by_name channel
    u = UserStruct.find uid
    c.del_user u
    u.part c
  end

  def privmsg uid, target, message
    data = message.split("\n")
    if data.nil?
      message.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{uid} PRIVMSG #{target} :#{x}\r\n" }
    else
      data.each { |d|
        if d.is_a? String
          d.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{uid} PRIVMSG #{target} :#{x}\r\n" }
        else
          d.each { |f| f.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{uid} PRIVMSG #{target} :#{x}\r\n" } }
        end
      }
    end
  end

  def notice uid, target, message
    data = message.split("\n")
    if data.nil?
      message.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{uid} NOTICE #{target} :#{x}\r\n" }
    else
      data.each { |d|
        if d.is_a? String
          d.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{uid} NOTICE #{target} :#{x}\r\n" }
        else
          d.each { |f| f.scan(/.{1,500}/m).each { |x| send_data @name, @sock, ":#{uid} NOTICE #{target} :#{x}\r\n" } }
        end
      }
    end
  end

  def wallop sid, message
    send_data @name, @sock, ":#{sid} OPERWALL :#{message}\r\n"
  end

  def squit sid, message
    send_data @name, @sock, "SQUIT #{sid} :#{message}\r\n"
  end

  def unkline sid, ip
    send_data @name, @sock, ":#{sid} UNKLINE * * #{ip}\r\n"
  end

  def chghost serversid, uid, host
    send_data @name, @sock, ":#{serversid} CHGHOST #{uid} #{host}\r\n"
    u = UserStruct.find uid
    u.chost = host
  end

  def ts6_fnc sid, newnick, uobj
    send_data @name, @sock, ":#{sid} ENCAP #{uobj.server.name} RSFNC #{uobj.uid} #{newnick} #{Time.now.to_i} #{uobj.ts}\r\n"
  end

  def ts6_save sid, uobj
    send_data @name, @sock, ":#{sid} SAVE #{uobj.uid} #{uobj.ts}\r\n"
    change_nick uobj.uid, uobj.uid
  end

  def server_kill sid, uid, server_name, reason
    send_data @name, @sock, ":#{sid} KILL #{uid} :#{server_name} (#{reason})\r\n"
    delete_user uid
  end

  def kill sobj, uid, message
    send_data @name, @sock, ":#{sobj.uid} KILL #{uid} :#{sobj.host}!#{sobj.nick} (#{message})\r\n"
    delete_user uid
  end

  def kick ouruid, theiruid, channel, message
    send_data @name, @sock, ":#{ouruid} KICK #{channel} #{theiruid} :#{message}\r\n"
    remove_user_from_channel theiruid, channel
  end

  def nick sid, newnick
    send_data @name, @sock, ":#{sid} NICK #{newnick} :#{Time.new.to_i}"
    change_nick newnick, sid
  end

  def get_channel_bans user
    bans = []
    cs = ChannelStruct.find_with_ban_against user
    return false if cs.empty?
    cs.each do |channel, ban|
      bans << {"channel" => channel.name, "ban_mask" => ban.length > 1 ? "#{ban[0]}!#{ban[1]}@#{ban[2]}" : ban[0] }
    end
    return bans
  end

  def get_channel_mutes user
    mutes = []
    cs = ChannelStruct.find_with_mute_against user
    return false if cs.empty?
    cs.each do |channel, mute|
      mutes << {"channel" => channel.name, "ban_mask" => mute.length > 1 ? "#{mute[0]}!#{mute[1]}@#{mute[2]}" : mute[0] }
    end
    return mutes
  end

  def remove_user_from_channel uid, channel
    c = ChannelStruct.find_by_name channel
    u = UserStruct.find uid
    c.del_user u
    u.part c
  end

  def get_user_channels uid
    u = UserStruct.find uid
    return if !u

    chans = []
    u.channels.each { |i|
      c = ChannelStruct.find_by_name i.name
      pfx = ""

      pfx += "~" if c.is_owner u and pfx.empty?
      pfx += "&" if c.is_admin u and pfx.empty?
      pfx += "@" if c.is_op u and pfx.empty?
      pfx += "%" if c.is_halfop u and pfx.empty?
      pfx += "+" if c.is_voice u and pfx.empty?
      if c.modes and c.modes.include? 's'
        pfx = '*'+pfx
      end
      chans << pfx+c.name
    }
    return chans
  end

  def delete_user uid
    u = UserStruct.find_by_uid uid
    u.server.usercount -= 1
    u.destroy if u
  end

  def change_nick nick, uid
    u = UserStruct.find_by_uid uid
    u.nick = nick
  end

  def get_uid_object uid
    return UserStruct.find uid
  end

  def get_nick_object nick
    return UserStruct.find nick
  end

  def get_nick_from_uid uid
    u = UserStruct.find uid
    return false if !u

    return u.nick
  end

  def get_uid_from_nick nick
    u = UserStruct.find nick
    return false if !u

    return u.uid
  end

  def is_oper_uid uid
    u = UserStruct.find uid
    return false if !u
    return u.isoper
  end

  def is_oper_nick nick
    u = UserStruct.find uid
    return false if !u
    return u.isoper
  end

  def is_chan_founder channel, uid
    u = UserStruct.find uid
    c = ChannelStruct.find_by_name channel
    return if !u or !c
    return c.is_owner u
  end

  def is_chan_admin channel, uid
    u = UserStruct.find uid
    c = ChannelStruct.find_by_name channel
    return if !u or !c
    return c.is_admin u
  end

  def is_chan_op channel, uid
    u = UserStruct.find uid
    c = ChannelStruct.find_by_name channel
    return if !u or !c
    return c.is_op u
  end

  def is_chan_halfop channel, uid
    u = UserStruct.find uid
    c = ChannelStruct.find_by_name channel
    return if !u or !c
    return c.is_halfop u
  end

  def is_chan_voice channel, uid
    u = UserStruct.find uid
    c = ChannelStruct.find_by_name channel
    return if !u or !c
    return c.is_voice u
  end

  def get_account_from_uid uid
    u = UserStruct.find uid
    return false if !u
    return u.nickserv
  end

  def get_chan_info channel
    return ChannelStruct.find_by_name channel
  end

  def get_users_in_channel channel
    c = ChannelStruct.find_by_name channel
    users = []
    c.get_users.each { |u|
      pfx = ""
      pfx += "~" if c.is_owner u and pfx.empty?
      pfx += "&" if c.is_admin u and pfx.empty?
      pfx += "@" if c.is_op u and pfx.empty?
      pfx += "%" if c.is_halfop u and pfx.empty?
      pfx += "+" if c.is_voice u and pfx.empty?
      ip = u.ip != '0' ? u.ip : u.chost
      users << "#{pfx}#{u.nick} [#{u.ident}@#{ip}]"
    }

    # FIXME
    u2 = []
    users = users.sort_by{|w| w.downcase}
    users.each { |c| u2 << c if c[0] == '~' }
    users.each { |c| u2 << c if c[0] == '&' }
    users.each { |c| u2 << c if c[0] == '@' }
    users.each { |c| u2 << c if c[0] == '%' }
    users.each { |c| u2 << c if c[0] == '+' }
    users.each { |c| u2 << c if !['~', '&', '@', '%', '+'].include? c[0] }
    return u2
  end

  def people_in_channel channel
    c = ChannelStruct.find_by_name channel
    return c.get_user_count
  end

  def get_channel_total
    return ChannelStruct.get_total_channels
  end

  def get_user_total
    return UserStruct.get_total_users
  end

  def get_oper_total
    return UserStruct.get_oper_count
  end

  def get_services_total
    return UserStruct.get_services_count
  end

  def does_channel_exist channel
    return ChannelStruct.find_by_name channel
  end

  def get_server_total
    return Server.servers_count
  end

  def initialize name, sock
    @name = name
    @sock = sock
    @bots = []
  end
end
