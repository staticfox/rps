require "active_record"

require_relative "../../libs/irc"

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
    LimitServ_Channel.establish_connection(@db)
    query = LimitServ_Channel.new
    query.channel = channel.downcase
    query.people  = @irc.people_in_channel channel
    query.time    = Time.now.to_i
    query.save
    @assigned_channels << channel.downcase
    LimitServ_Channel.connection.disconnect!
  end

  def remove_channel channel
    LimitServ_Channel.establish_connection(@db)
    query = LimitServ_Channel.where(channel: channel.downcase)
    return false if query.count == 0
    @assigned_channels.delete(channel.downcase)
    query.delete_all
    @irc.client_set_mode @client_sid, "#{channel} -l"
    LimitServ_Channel.connection.disconnect!
    return true
  end

  def sendto_debug message
    @ls["debug_channels"].split(',').each { |i|
      @irc.privmsg @client_sid, i, message
    }
  end

  def join_channels
    LimitServ_Channel.establish_connection(@db)
    queries = LimitServ_Channel.select(:channel)
    return if queries.count == 0
    queries.each { |query|
      @irc.client_join_channel @client_sid, query.channel
      @irc.client_set_mode @client_sid, "#{query.channel} +o #{@client_sid}"
      sendto_debug "JOINED: #{query.channel}"
      @assigned_channels << query.channel
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
    LimitServ_Channel.establish_connection(@db)
    queries = LimitServ_Channel.where('time <= ?', Time.now.to_i)
    return if queries.count == 0
    array = []
    queries.each { |query|
      oldlimit = query.people.to_i
      newlimit = @irc.people_in_channel query.channel
      newlimit = newlimit.to_i
      channellimit = newlimit
      newlimit = limits newlimit
      #puts "0 - #{query.channel} - #{oldlimit} - #{newlimit}"
      calc = newlimit - oldlimit
      ofr = "FALSE"
      ofr = "TRUE" if calc <= -2 or calc >= 2
      #puts "Offset: #{calc}"
      string = "#{query.channel} - Current Amount: #{channellimit} - Current Limit: #{newlimit} - Offset: #{calc} - Offset Reached: #{ofr}"
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
    LimitServ_Channel.establish_connection(@db)
    begin
      query = LimitServ_Channel.find_by(channel: data[3].downcase)
      query.update(people: setval.to_i, time: Time.new.to_i) if query
    rescue Exception => e
      LimitServ_Channel.connection.disconnect!
      puts e.message
      sendto_debug "********* EXCEPTION *********"
      sendto_debug e.message
      sendto_debug e.backtrace
      sendto_debug "********* END OF EXCEPTION *********"
    end
    LimitServ_Channel.connection.disconnect!
  end

  def run_checks
    LimitServ_Channel.establish_connection(@db)
    queries = LimitServ_Channel.where('time <= ?', Time.now.to_i)
    return if queries.count == 0
    queries.each { |query|
      oldlimit = query.people.to_i
      newlimit = @irc.people_in_channel query.channel
      newlimit = newlimit.to_i

      newlimit = limits newlimit
      calc = newlimit - oldlimit

      if calc <= -2 or calc >= 2

        @channellist.each { |channel| return if channel == query.channel }
        @channellist.push(query.channel)

        Thread.new do
          sleep 60
          @channellist.delete(query.channel)

          oldlimit = query.people.to_i
          newlimit = @irc.people_in_channel query.channel
          newlimit = newlimit.to_i

          currentcount = newlimit

          newlimit = limits newlimit
          calc = newlimit - oldlimit

          next if oldlimit == newlimit

          begin
            query.update(people: newlimit, time: Time.new.to_i)
          rescue Exception => e
            puts e.message
            sendto_debug "********* EXCEPTION *********"
            sendto_debug e.message
            sendto_debug e.backtrace
            sendto_debug "********* END OF EXCEPTION *********"
          end

          @irc.client_set_mode @client_sid, "#{query.channel} +l #{newlimit}"
          sendto_debug "NEW LIMIT: #{query.channel} - #{newlimit}, Old Limit - #{oldlimit}, Offset: #{calc}, Actual Count: #{currentcount}"
        end
      end
    }
    LimitServ_Channel.connection.disconnect!
  end

  def _internal_nuke
    @assigned_channels.each { |x| @irc.client_set_mode @client_sid, "#{x} -l" }
  end

  def handle_privmsg hash
    target = hash["from"]

    case hash["command"].downcase
    when "help"
      # TODO
      if !hash["parameters"].empty?
        @irc.notice @client_sid, target, "***** #{@ls["nick"]} Help *****"
        @irc.notice @client_sid, target, "Extended help not implemented yet."
        @irc.notice @client_sid, target, "***** End of Help *****"
        return
      end

      @irc.notice @client_sid, target, "***** #{@ls["nick"]} Help *****"
      @irc.notice @client_sid, target, "#{@ls["nick"]} allows channel owners to limit the amount of joins that happen in certain amount of time. This is to prevent join floods."
      @irc.notice @client_sid, target, "For more info a command, type '/msg #{@ls["nick"]} help <command>' (without the quotes) for more information."
      @irc.notice @client_sid, target, "The following commands are available:"
      @irc.notice @client_sid, target, "LIST            List channels that #{@ls["nick"]} monitors." if @irc.is_oper_uid target
      @irc.notice @client_sid, target, "REQUEST         Request #{@ls["nick"]} to protect a channel from join floods."
      @irc.notice @client_sid, target, "REMOVE          Stop #{@ls["nick"]} from protecting a channel."
      @irc.notice @client_sid, target, "NUKE            Unsets all channel limits where #{@ls["nick"]} lives." if @irc.is_oper_uid target
      @irc.notice @client_sid, target, "***** End of Help *****"
      @irc.notice @client_sid, target, "If you're having trouble or you need additional help, you may want to join the help channel #help."

    when "list"
      return @irc.notice @client_sid, target, "[ERROR] You must be an oper to use this command." if !@irc.is_oper_uid target
      stats_channels.each { |line| @irc.notice @client_sid, target, line }

    when "nuke"
      return @irc.notice @client_sid, target, "[ERROR] You must be an oper to use this command." if !@irc.is_oper_uid target
      LimitServ_Channel.establish_connection(@db)
      queries = LimitServ_Channel.all
      return if queries.count == 0
      queries.each { |query|
        query.update(time: Time.now.to_i)
        @irc.client_set_mode @client_sid, "#{query.channel} -l"
      }
      sendto_debug "#{@irc.get_nick_from_uid target} unset the limit in all channels"
      @irc.wallop @client_sid, "\x02#{@irc.get_nick_from_uid target}\x02 used \x02NUKE\x02 unsetting the limit in all channels"

    when "request"
      return @irc.notice @client_sid, target, "[ERROR] No chatroom was specified." if hash["parameters"].empty?
      return @irc.notice @client_sid, target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return @irc.notice @client_sid, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to add #{@ls["nick"]} to the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return @irc.notice @client_sid, target, "[ERROR] This channel is already signed up for #{@ls["nick"]}." if @assigned_channels.include? hash["parameters"]
      signup_channel hash["parameters"]
      @irc.notice @client_sid, target, "[SUCCESS] #{hash["parameters"]} will now be monitored by #{@ls["nick"]}."
      @irc.client_join_channel @client_sid, hash["parameters"]
      @irc.client_set_mode @client_sid, "#{hash["parameters"]} +o #{@client_sid}"
      sendto_debug "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"

    when "remove"
      return @irc.notice @client_sid, target, "[ERROR] No chatroom was specified." if hash["parameters"].empty?
      return @irc.notice @client_sid, target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return @irc.notice @client_sid, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to remove #{@ls["nick"]} from the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return @irc.notice @client_sid, target, "[ERROR] This channel is not signed up for #{@ls["nick"]}." if !@assigned_channels.include? hash["parameters"]
      remove_channel hash["parameters"]
      @irc.notice @client_sid, target, "[SUCCESS] #{hash["parameters"]} will not be monitored by #{@ls["nick"]}."
      @irc.client_part_channel @client_sid, hash["parameters"], "#{@irc.get_nick_from_uid(@client_sid)} removed by #{@irc.get_nick_from_uid(target)}"
      sendto_debug "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"

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
    @ls = @config["limitserv"]
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000002"
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    LimitServ_Channel.connection.disconnect!
    @db = @config["connections"]["databases"]["test"]
    @channellist = []

    @e.on_event do |type, name, sock|
      if type == "LimitServ-Init"
        @irc = IRCLib.new name, sock, @db
        join_channels
      end
    end

    @e.on_event do |type, hash|
      if type == "LimitServ-Chat"
        @irc = IRCLib.new hash["name"], hash["sock"], @db if @irc.nil?
        if hash["target"] == @client_sid
          handle_privmsg hash if hash["msgtype"] == "PRIVMSG" or hash["msgtype"] == "NOTICE"
        end
      end
    end

    @e.on_event do |type, name, sock, data|
      if type == "IRCChanJoin" or type == "IRCChanPart" or type == "IRCPing" or type == "IRCClientQuit"
        config = @c.Get if @irc.nil?
        @irc = IRCLib.new name, sock, @db if @irc.nil?
        run_checks
      elsif type == "IRCChanSJoin"
        burst_data data
      end
    end

    @e.on_event do |signal, param|
      if signal == "Error"
        _internal_nuke
      end
    end

  end
end
