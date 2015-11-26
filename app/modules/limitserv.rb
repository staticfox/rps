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

  def is_channel_signedup channel
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    query = LimitServ_Channel.where('Channel = ?', channel)
    return true if query.count == 1
    LimitServ_Channel.connection.disconnect!
    return false
  end


  def signup_channel channel
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    query = LimitServ_Channel.new
    query.Channel = channel.downcase
    query.People = @irc.people_in_channel channel
    query.Time = Time.now.to_i
    query.save
    LimitServ_Channel.connection.disconnect!
  end

  def remove_channel channel
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    query = LimitServ_Channel.where('Channel = ?', channel.downcase)
    return false if query.count == 0
    query.delete_all
    @irc.client_set_mode @client_sid, "#{channel} -l"
    LimitServ_Channel.connection.disconnect!
    return true
  end

  def join_channels
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    queries = LimitServ_Channel.select(:Channel)
    return if queries.count == 0
    queries.each do |query|
      @irc.client_join_channel @client_sid, query.Channel
      @irc.client_set_mode @client_sid, "#{query.Channel} +o #{@client_sid}"
      @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "JOINED: #{query.Channel}"
    end
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
    queries.each do |query|
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
    end
    LimitServ_Channel.connection.disconnect!
    return array
  end

  def run_checks
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    queries = LimitServ_Channel.where('Time <= ?', Time.now.to_i)
    return if queries.count == 0
    queries.each do |query|
      oldlimit = query.People.to_i
      newlimit = @irc.people_in_channel query.Channel
      newlimit = newlimit.to_i

      newlimit = limits newlimit
      puts "0 - #{query.Channel} - #{oldlimit} - #{newlimit}"
      calc = newlimit - oldlimit
      puts "Offset: #{calc}"

      if calc <= -2 or calc >= 2 then

        puts "Channel List Before Checking - #{@channellist}"

        @channellist.each do |channel|
          return if channel == query.Channel
        end

        @channellist.push(query.Channel)

        puts "Added channel to array. - #{@channellist}"

        Thread.new do
          puts "1 - Spawnned thread for checking #{query.Channel} - Waiting 60 seconds..."
          sleep 60
          puts "Running Thread..."

          @channellist.delete(query.Channel)
          puts "Channel list after channel removed. - #{@channellist}"

          oldlimit = query.People.to_i
          puts "test 1"
          puts "Query Channel: #{query.Channel}"
          newlimit = @irc.people_in_channel query.Channel
          puts "test 2"
          newlimit = newlimit.to_i

          currentcount = newlimit

          puts "test 3"

          newlimit = limits newlimit
          puts "1 - #{query.Channel} - #{oldlimit} - #{newlimit}"
          calc = newlimit - oldlimit
          puts "1 - Offset: #{calc}"

          next if oldlimit == newlimit

          LimitServ_Channel.connection.execute("UPDATE `limit_serv_channels` SET `People` = '#{newlimit}', `Time` = '#{Time.now.to_i}' WHERE `Channel` = '#{query.Channel}';")
          puts "Updated MySQL"
          @irc.client_set_mode @client_sid, "#{query.Channel} +l #{newlimit}"
          puts "Updated Channel Mode"
          @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "NEW LIMIT: #{query.Channel} - #{newlimit}, Old Limit - #{oldlimit}, Offset: #{calc}, Actual Count: #{currentcount}"
        end
      end
    end
    LimitServ_Channel.connection.disconnect!
  end

  def handle_privmsg hash
    target = hash["from"]
    @irc.privmsg @client_sid, target, "This is only a test." if hash["command"] == "!test"

    if hash["command"].downcase == "help" then
      @irc.notice @client_sid, target, "***** LimitServ Help *****"
      @irc.notice @client_sid, target, "LimitServ allows channel owners to limit the amount of joins that happen in certain amount of time. This is to prevent join floods."
      #@irc.notice @client_sid, target, "For more info a command, type '/msg LimitServ help <command>' (without the quotes) for more information."
      @irc.notice @client_sid, target, "The following commands are available:"
      @irc.notice @client_sid, target, "LIST            List channels that LimitServ monitors." if @irc.is_oper_uid target
      @irc.notice @client_sid, target, "REQUEST         Request LimitServ to protect a channel from join floods."
      @irc.notice @client_sid, target, "REMOVE          Stop LimitServ from protecting a channel."
      @irc.notice @client_sid, target, "NUKE            Unsets all channel limits where LimitServ lives." if @irc.is_oper_uid target
      @irc.notice @client_sid, target, "***** End of Help *****"
      @irc.notice @client_sid, target, "If you're having trouble or you need additional help, you may want to join the help channel #help."
    end

    if hash["command"].downcase == "list" then
      if !@irc.is_oper_uid target then
        @irc.notice @client_sid, target, "[ERROR] You must be an oper to use this command."
        return
      end
      stats_channels.each do |line|
        @irc.notice @client_sid, target, line
      end
    end

    if hash["command"].downcase == "nuke" then
      if !@irc.is_oper_uid target then
        @irc.notice @client_sid, target, "[ERROR] You must be an oper to use this command."
        return
      end
      LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
      queries = LimitServ_Channel.all
      return if queries.count == 0
      queries.each do |query|
        LimitServ_Channel.connection.execute("UPDATE `limit_serv_channels` SET `People` = '#{query.People}', `Time` = '#{Time.now.to_i}' WHERE `Channel` = '#{query.Channel}';")
        puts "Updated MySQL"
        @irc.client_set_mode @client_sid, "#{query.Channel} -l"
        puts "Updated Channel Mode"
        @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "[!NUKE!] - #{query.Channel}"
      end
    end


    if hash["command"].downcase == "request" then
      if hash["parameters"].nil? then
        @irc.notice @client_sid, target, "[ERROR] No chatroom was specified."
        return
      end

      if !@irc.does_channel_exist hash["parameters"] then
        @irc.notice @client_sid, target, "[ERROR] The channel does not exist on this network."
        return
      end

      if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target then
        @irc.notice @client_sid, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to add LimitServ to the channel."
        return
      end

      if is_channel_signedup hash["parameters"] then
        @irc.notice @client_sid, target, "[ERROR] This channel is already signed up for LimitServ."
        return
      end

      signup_channel hash["parameters"]
      @irc.notice @client_sid, target, "[SUCCESS] #{hash["parameters"]} will now be monitored by LimitServ."
      @irc.client_join_channel @client_sid, hash["parameters"]
      @irc.client_set_mode @client_sid, "#{hash["parameters"]} +o #{@client_sid}"
      @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"
    end

    if hash["command"].downcase == "remove" then
      if hash["parameters"].nil? then
        @irc.notice @client_sid, target, "[ERROR] No chatroom was specified."
        return
      end

      if !@irc.does_channel_exist hash["parameters"] then
        @irc.notice @client_sid, target, "[ERROR] The channel does not exist on this network."
        return
      end

      if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target then
        @irc.notice @client_sid, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to remove LimitServ from the channel."
        return
      end

      if !is_channel_signedup hash["parameters"] then
        @irc.notice @client_sid, target, "[ERROR] This channel is not signed up for LimitServ."
        return
      end

      remove_channel hash["parameters"]
      @irc.notice @client_sid, target, "[SUCCESS] #{hash["parameters"]} will not be monitored by LimitServ."
      @irc.client_part_channel @client_sid, hash["parameters"]
      @irc.privmsg @client_sid, @config["debug-channels"]["limitserv"], "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"
    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = c.Get
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000002"
    LimitServ_Channel.establish_connection(@config["connections"]["databases"]["test"])
    LimitServ_Channel.connection.disconnect!
    @channellist = []

    @e.on_event do |type, name, sock|
      if type == "LimitServ-Init" then
        @irc = IRCLib.new name, sock, @config["connections"]["databases"]["test"]
        join_channels
      end
    end

    @e.on_event do |type, hash|
      if type == "LimitServ-Chat" then
        @irc = IRCLib.new hash["name"], hash["sock"], @config["connections"]["databases"]["test"] if @irc.nil?
        if hash["target"] == @client_sid then
          handle_privmsg hash if hash["msgtype"] == "PRIVMSG" or hash["msgtype"] == "NOTICE"
        end
      end
    end

    @e.on_event do |type, name, sock, data|
      if type == "IRCChanJoin" or type == "IRCChanPart" or type == "IRCPing" or type == "IRCClientQuit" then
        config = @c.Get if @irc.nil?
        @irc = IRCLib.new name, sock, @config["connections"]["databases"]["test"] if @irc.nil?
        run_checks
      end
    end
  end
end