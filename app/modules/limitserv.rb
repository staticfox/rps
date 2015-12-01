require "active_record"

require_relative "../libs/irc"

class LimitServ_Channel < ActiveRecord::Base
end

class LimitServCore

  @irc = nil
  @channellist = []

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def signup_channel channel
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    query = LimitServ_Channel.new
    query.Channel = channel.downcase
    query.People = @irc.people_in_channel channel
    query.Time = Time.now.to_i
    query.save
    @assigned_channels << channel.downcase
    LimitServ_Channel.connection.disconnect!
  end

  def remove_channel channel
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    query = LimitServ_Channel.where('Channel = ?', channel.downcase)
    return false if query.count == 0
    @assigned_channels.delete(channel.downcase)
    query.delete_all
    @irc.client_set_mode @client_sid, "#{channel} -l"
    LimitServ_Channel.connection.disconnect!
    return true
  end

  def join_channels
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    queries = LimitServ_Channel.select(:Channel)
    return if queries.count == 0
    queries.each { |query|
      @irc.client_join_channel @client_sid, query.Channel
      @irc.client_set_mode @client_sid, "#{query.Channel} +o #{@client_sid}"
      @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "JOINED: #{query.Channel}"
      @assigned_channels << query.Channel
    }
    LimitServ_Channel.connection.disconnect!
  end

  def limits newlimit
    return newlimit + 5 if newlimit <= 30
    return newlimit + 6 if newlimit <= 40 and newlimit >= 31
    return newlimit + 7 if newlimit <= 50 and newlimit >= 41
    return newlimit + 8 if newlimit <= 60 and newlimit >= 51
    return newlimit + 9 if newlimit <= 70 and newlimit >= 61
    return newlimit + 10 if newlimit <= 80 and newlimit >= 71
    return newlimit + 11 if newlimit <= 90 and newlimit >= 81
    return newlimit + 12 if newlimit <= 100 and newlimit >= 91
    return newlimit + 13 if newlimit <= 110 and newlimit >= 101
    return newlimit + 14 if newlimit <= 120 and newlimit >= 111
    return newlimit + 15 if newlimit <= 130 and newlimit >= 121
    return newlimit + 16 if newlimit >= 131
  end

  def stats_channels
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    queries = LimitServ_Channel.where('Time <= ?', Time.now.to_i)
    return if queries.count == 0
    array = []
    queries.each { |query|
      oldlimit = query.People.to_i
      newlimit = @irc.people_in_channel query.Channel
      newlimit = newlimit.to_i
      channellimit = newlimit
      newlimit = limits newlimit
      #puts "0 - #{query.Channel} - #{oldlimit} - #{newlimit}"
      calc = newlimit - oldlimit
      ofr = "FALSE"
      ofr = "TRUE" if calc <= -2 or calc >= 2
      #puts "Offset: #{calc}"
      string = "#{query.Channel} - Current Amount: #{channellimit} - Current Limit: #{newlimit} - Offset: #{calc} - Offset Reached: #{ofr}"
      array.push(string)
    }
    LimitServ_Channel.connection.disconnect!
    return array
  end

  def burst_data data
    if data[4].include? 'l'
      setval = data[5].to_i
    else
      setval = 0
    end
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    LimitServ_Channel.connection.execute("UPDATE `limit_serv_channels` SET `People` = '#{setval}', `Time` = '#{Time.now.to_i}' WHERE `Channel` = '#{data[3].downcase}';")
    LimitServ_Channel.connection.disconnect!
  end

  def run_checks
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    queries = LimitServ_Channel.where('Time <= ?', Time.now.to_i)
    return if queries.count == 0
    queries.each { |query|
      oldlimit = query.People.to_i
      newlimit = @irc.people_in_channel query.Channel
      newlimit = newlimit.to_i

      newlimit = limits newlimit
      puts "0 - #{query.Channel} - #{oldlimit} - #{newlimit}"
      calc = newlimit - oldlimit
      puts "Offset: #{calc}"

      if calc <= -2 or calc >= 2

        puts "Channel List Before Checking - #{@channellist}"

        @channellist.each { |channel| return if channel == query.Channel }

        @channellist.push(query.Channel)

        puts "Added channel to array. - #{@channellist}"

        Thread.new do
          puts "1 - Spawnned thread for checking #{query.Channel} - Waiting 60 seconds..."
          sleep 60

          @channellist.delete(query.Channel)

          oldlimit = query.People.to_i
          newlimit = @irc.people_in_channel query.Channel
          newlimit = newlimit.to_i

          currentcount = newlimit

          newlimit = limits newlimit
          calc = newlimit - oldlimit

          next if oldlimit == newlimit

          LimitServ_Channel.connection.execute("UPDATE `limit_serv_channels` SET `People` = '#{newlimit}', `Time` = '#{Time.now.to_i}' WHERE `Channel` = '#{query.Channel}';")
          @irc.client_set_mode @client_sid, "#{query.Channel} +l #{newlimit}"
          @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "NEW LIMIT: #{query.Channel} - #{newlimit}, Old Limit - #{oldlimit}, Offset: #{calc}, Actual Count: #{currentcount}"
        end
      end
    }
    LimitServ_Channel.connection.disconnect!
  end

  def _internal_nuke
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    queries = LimitServ_Channel.all
    return if queries.count == 0
    queries.each { |query|
      LimitServ_Channel.connection.execute("UPDATE `limit_serv_channels` SET `People` = '#{query.People}', `Time` = '#{Time.now.to_i}' WHERE `Channel` = '#{query.Channel}';")
      @irc.client_set_mode @client_sid, "#{query.Channel} -l"
    }
  end

  def handle_privmsg hash
    target = hash["from"]

    case hash["command"].downcase
    when "help"
      # TODO
      if !hash["parameters"].empty?
        @irc.notice @client_sid, target, "***** LimitServ Help *****"
        @irc.notice @client_sid, target, "Extended help not implemented yet."
        @irc.notice @client_sid, target, "***** End of Help *****"
        return
      end

      @irc.notice @client_sid, target, "***** LimitServ Help *****"
      @irc.notice @client_sid, target, "LimitServ allows channel owners to limit the amount of joins that happen in certain amount of time. This is to prevent join floods."
      @irc.notice @client_sid, target, "For more info a command, type '/msg LimitServ help <command>' (without the quotes) for more information."
      @irc.notice @client_sid, target, "The following commands are available:"
      @irc.notice @client_sid, target, "LIST            List channels that LimitServ monitors." if @irc.is_oper_uid target
      @irc.notice @client_sid, target, "REQUEST         Request LimitServ to protect a channel from join floods."
      @irc.notice @client_sid, target, "REMOVE          Stop LimitServ from protecting a channel."
      @irc.notice @client_sid, target, "NUKE            Unsets all channel limits where LimitServ lives." if @irc.is_oper_uid target
      @irc.notice @client_sid, target, "***** End of Help *****"
      @irc.notice @client_sid, target, "If you're having trouble or you need additional help, you may want to join the help channel #help."

    when "list"
      return @irc.notice @client_sid, target, "[ERROR] You must be an oper to use this command." if !@irc.is_oper_uid target
      stats_channels.each { |line| @irc.notice @client_sid, target, line }

    when "nuke"
      return @irc.notice @client_sid, target, "[ERROR] You must be an oper to use this command." if !@irc.is_oper_uid target
      LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
      queries = LimitServ_Channel.all
      return if queries.count == 0
      queries.each { |query|
        LimitServ_Channel.connection.execute("UPDATE `limit_serv_channels` SET `People` = '#{query.People}', `Time` = '#{Time.now.to_i}' WHERE `Channel` = '#{query.Channel}';")
        @irc.client_set_mode @client_sid, "#{query.Channel} -l"
      }
      @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "#{@irc.get_nick_from_uid target} unset the limit in all channels"
      @irc.wallop @client_sid, "\x02#{@irc.get_nick_from_uid target}\x02 used \x02NUKE\x02 unsetting the limit in all channels"

    when "request"
      return @irc.notice @client_sid, target, "[ERROR] No chatroom was specified." if hash["parameters"].empty?
      return @irc.notice @client_sid, target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return @irc.notice @client_sid, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to add LimitServ to the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return @irc.notice @client_sid, target, "[ERROR] This channel is already signed up for LimitServ." if @assigned_channels.include? hash["parameters"]
      signup_channel hash["parameters"]
      @irc.notice @client_sid, target, "[SUCCESS] #{hash["parameters"]} will now be monitored by LimitServ."
      @irc.client_join_channel @client_sid, hash["parameters"]
      @irc.client_set_mode @client_sid, "#{hash["parameters"]} +o #{@client_sid}"
      @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"

    when "remove"
      return @irc.notice @client_sid, target, "[ERROR] No chatroom was specified." if hash["parameters"].empty?
      return @irc.notice @client_sid, target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return @irc.notice @client_sid, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to remove LimitServ from the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return @irc.notice @client_sid, target, "[ERROR] This channel is not signed up for LimitServ." if !@assigned_channels.include? hash["parameters"]
      remove_channel hash["parameters"]
      @irc.notice @client_sid, target, "[SUCCESS] #{hash["parameters"]} will not be monitored by LimitServ."
      @irc.client_part_channel @client_sid, hash["parameters"], "#{@irc.get_nick_from_uid(@client_sid)} removed by #{@irc.get_nick_from_uid(target)}"
      @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"

    else
      @irc.notice @client_sid, target, "#{hash["command"].upcase} is an unknown command."

    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @assigned_channels = []

    @config = c.Get
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000002"
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    LimitServ_Channel.connection.disconnect!
    @channellist = []

    @e.on_event do |type, name, sock|
      if type == "LimitServ-Init"
        @irc = IRCLib.new name, sock, @config["connections"]["databases"]["test"]
        join_channels
      end
    end

    @e.on_event do |type, hash|
      if type == "LimitServ-Chat"
        @irc = IRCLib.new hash["name"], hash["sock"], @config["connections"]["databases"]["test"] if @irc.nil?
        if hash["target"] == @client_sid
          handle_privmsg hash if hash["msgtype"] == "PRIVMSG" or hash["msgtype"] == "NOTICE"
        end
      end
    end

    @e.on_event do |type, name, sock, data|
      if type == "IRCChanJoin" or type == "IRCChanPart" or type == "IRCPing" or type == "IRCClientQuit"
        config = @c.Get if @irc.nil?
        @irc = IRCLib.new name, sock, @config["connections"]["databases"]["test"] if @irc.nil?
        run_checks
      elsif type == "IRCChanSJoin"
        burst_data data
      end
    end
  end
end