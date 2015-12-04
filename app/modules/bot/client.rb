require "active_record"

require_relative "../../libs/irc"

class BotChannel < ActiveRecord::Base
end

class BotClient

  def me_user_notice recp, message
    @irc.notice @client_sid, recp, message
  end

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def connect_client
    joined = []
    @irc.add_client @parameters["sid"], @client_sid, @parameters["server_name"], @bot["nick"], @bot["modes"], @bot["user"], @bot["host"], @bot["real"]
    # FIXME zip arrays?
    @bot["idle_channels"].split(',').each { |i|
      next if joined.include? i or @assigned_channels.include? i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@bot["nick"]}"
    }
    @bot["debug_channels"].split(',').each { |i|
      next if joined.include? i or @assigned_channels.include? i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@bot["nick"]}"
    }
    @bot["control_channels"].split(',').each { |i|
      next if joined.include? i or @assigned_channels.include? i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@bot["nick"]}"
    }
  end

  def sendto_debug message
    @bot["debug_channels"].split(',').each { |i|
      @irc.privmsg @client_sid, i, message
    }
  end

  def signup_channel channel
    BotChannel.establish_connection(@db)
    query = BotChannel.new
    query.channel = channel.downcase
    query.save
    BotChannel.connection.disconnect!
    @assigned_channels << channel.downcase
  end

  def remove_channel channel
    BotChannel.establish_connection(@db)
    query = BotChannel.where(channel: channel.downcase)
    query.delete_all
    BotChannel.connection.disconnect!
    @assigned_channels.delete(channel.downcase)
    return
  end

  def join_channels
    BotChannel.establish_connection(@db)
    queries = BotChannel.select(:channel)
    return if queries.count == 0
    queries.each do |query|
      @irc.client_join_channel @client_sid, query.channel
      @irc.client_set_mode @client_sid, "#{query.channel} +o #{@client_sid}"
      sendto_debug "JOINED: #{query.channel}"
      @assigned_channels << query.channel
    end
    BotChannel.connection.disconnect!
  end

  def shutdown message
    @irc.remove_client @client_sid, message
  end

  def handle_privmsg hash

    if @assigned_channels.include? hash["target"].downcase
      @e.Run "Bot-Chat", hash
      return
    end

    target = hash["target"]
    target = hash["from"] if target == @client_sid

    return if hash["target"] != @client_sid

    case hash["command"].downcase
    when "help"
      me_user_notice target, "***** #{@bot["nick"]} Help *****"
      me_user_notice target, "#{@bot["nick"]} is a utility bot that adds functionality to your channel."
      me_user_notice target, "The following commands are available:"
      me_user_notice target, "REQUEST                   Request #{@bot["nick"]} for your channel."
      me_user_notice target, "REMOVE                    Remove #{@bot["nick"]} from your channel."
      me_user_notice target, "***** In Channel Commands *****"
      me_user_notice target, "!w <zip/city, state>      Displays the current weather conditions."
      me_user_notice target, "!g <google search>        Searches google for what you specified."
      me_user_notice target, "!q                        Displays a random quote from your channel."
      me_user_notice target, "!q <add>                  Adds a quote."
      me_user_notice target, "!q <del> <number>         Delete (number)'s quote from the databases."
      me_user_notice target, "\x02NOTE\x02 !q is an alias of !quote, !w is an alias of !weather, !g is an alias of !google"
      me_user_notice target, "***** End of Help *****"
      me_user_notice target, "If you're having trouble or you need additional help, you may want to join the help channel #help."

    when "request"
      return me_user_notice target, "[ERROR] No chatroom was specified." if hash["parameters"].empty?
      return me_user_notice target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return me_user_notice target, "[ERROR] You must be founder of #{hash["parameters"]} in order to add #{@bot["nick"]} to the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return me_user_notice target, "[ERROR] This channel is already signed up for #{@bot["nick"]}." if @assigned_channels.include? hash["parameters"]
      signup_channel hash["parameters"]
      me_user_notice target, "[SUCCESS] #{@bot["nick"]} has joined #{hash["parameters"]}."
      @irc.client_join_channel @client_sid, hash["parameters"]
      @irc.client_set_mode @client_sid, "#{hash["parameters"]} +o #{@client_sid}"
      sendto_debug "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"

    when "remove"
      return me_user_notice target, "[ERROR] No chatroom was specified." if hash["parameters"].empty?
      return me_user_notice target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return me_user_notice target, "[ERROR] You must be founder of #{hash["parameters"]} in order to remove #{@bot["nick"]} from the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return me_user_notice target, "[ERROR] This channel is not signed up for #{@bot["nick"]}." if !@assigned_channels.include? hash["parameters"]

      remove_channel hash["parameters"]
      me_user_notice target, "[SUCCESS] #{@bot["nick"]} has left #{hash["parameters"]}."
      @irc.client_part_channel @client_sid, hash["parameters"], "#{@irc.get_nick_from_uid(@client_sid)} removed by #{@irc.get_nick_from_uid(target)}"
      sendto_debug "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"

    else
      return me_user_notice target, "\x02#{hash["command"].upcase}\x02 is an unknown command"
    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @assigned_channels = []

    @config = c.Get

    @bot = @config["bot"]
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000003"
    @initialized = false
    @db = @config["connections"]["databases"]["test"]
    @e.on_event do |type, name, sock|
      if type == "IRCClientInit"
        @config = @c.Get
        @bot = @config["bot"]
        @db  = @config["connections"]["databases"]["test"]
        @irc = IRCLib.new name, sock, @db
        connect_client
        sleep 1
        join_channels
        @initialized = true
      end
    end

    @e.on_event do |type, nick, server|
      if type == "EUID"
        @irc.collide nick, server
      end
    end

    @e.on_event do |type, hash|
      if type == "IRCChat"
        if !@initialized
          @config = @c.Get
          @bot = @config["bot"]
          @db  = @config["connections"]["databases"]["test"]
          @irc = IRCLib.new hash["name"], hash["sock"], @db
          connect_client
          sleep 1
          join_channels
          @initialized = true
          sleep 1
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end

    @e.on_event do |signal, param|
      shutdown param if signal == "Shutdown"
    end

  end
end
