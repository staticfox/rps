require "active_record"

require_relative "../libs/irc"

class BotChannel < ActiveRecord::Base
end

class BotClient

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def connect_client
    @irc.add_client @parameters["sid"], "#{@client_sid}", "Bot", "+ioS", "Bot", "GeeksIRC.net", "Bot"
  end

  def is_channel_signedup channel
    BotChannel.establish_connection(@config["connections"]["databases"]["test"])
    query = BotChannel.where('Channel = ?', channel)
    return true if query.count == 1
    BotChannel.connection.disconnect!
    return false
  end


  def signup_channel channel
    BotChannel.establish_connection(@config["connections"]["databases"]["test"])
    query = BotChannel.new
    query.Channel = channel.downcase
    query.save
    BotChannel.connection.disconnect!
  end

  def remove_channel channel
    BotChannel.establish_connection(@config["connections"]["databases"]["test"])
    query = BotChannel.where('Channel = ?', channel.downcase)
    (BotChannel.connection.disconnect!; return false) if query.count == 0
    query.delete_all
    BotChannel.connection.disconnect!
    return true
  end

  def join_channels
    BotChannel.establish_connection(@config["connections"]["databases"]["test"])
    queries = BotChannel.select(:Channel)
    return if queries.count == 0
    queries.each do |query|
      @irc.client_join_channel @client_sid, query.Channel
      @irc.client_set_mode @client_sid, "#{query.Channel} +o #{@client_sid}"
      @irc.privmsg @client_sid, "#debug", "JOINED: #{query.Channel}"
    end
    BotChannel.connection.disconnect!
  end

  def handle_privmsg hash
    @e.Run "Bot-Chat", hash
    target = hash["target"]
    target = hash["from"] if hash["target"] == @client_sid
    @irc.privmsg @client_sid, target, "This is only a test." if hash["command"] == "!test"
    #@irc.privmsg @client_sid, "Ryan", "#{hash['from']} is an oper." if @irc.is_oper_uid hash["from"]

    return if hash["target"] != @client_sid

    if hash["command"].downcase == "help"
      @irc.notice @client_sid, target, "***** Bot Help *****"
      @irc.notice @client_sid, target, "Bot allows channel owners to limit the amount of joins that happen in certain amount of time. This is to prevent join floods."
      #@irc.notice @client_sid, target, "For more info a command, type '/msg LimitServ help <command>' (without the quotes) for more information."
      @irc.notice @client_sid, target, "The following commands are available:"
      #@irc.notice @client_sid, target, "LIST                      List channels that LimitServ monitors." if @irc.is_oper_uid target
      @irc.notice @client_sid, target, "REQUEST                   Request Bot for your channel."
      @irc.notice @client_sid, target, "REMOVE                    Remove Bot from your channel."
      @irc.notice @client_sid, target, "***** End of Help *****"
      @irc.notice @client_sid, target, "If you're having trouble or you need additional help, you may want to join the help channel #help."
    end

    if hash["command"].downcase == "request"
      if hash["parameters"].nil?
        @irc.notice @client_sid, target, "[ERROR] No chatroom was specified."
        return
      end

      if !@irc.does_channel_exist hash["parameters"]
        @irc.notice @client_sid, target, "[ERROR] The channel does not exist on this network."
        return
      end

      if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
        @irc.notice @client_sid, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to add Bot to the channel."
        return
      end

      if is_channel_signedup hash["parameters"]
        @irc.notice @client_sid, target, "[ERROR] This channel is already signed up for Bot."
        return
      end

      signup_channel hash["parameters"]
      @irc.notice @client_sid, target, "[SUCCESS] Bot has joined #{hash["parameters"]}."
      @irc.client_join_channel @client_sid, hash["parameters"]
      @irc.client_set_mode @client_sid, "#{hash["parameters"]} +o #{@client_sid}"
      @irc.privmsg @client_sid, "#debug", "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})" if @irc.is_chan_founder hash["parameters"], target
      @irc.privmsg @client_sid, "#debug", "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)}) [OPER Override]" if @irc.is_oper_uid target
    end

    if hash["command"].downcase == "remove"
      if hash["parameters"].nil?
        @irc.notice @client_sid, target, "[ERROR] No chatroom was specified."
        return
      end

      if !@irc.does_channel_exist hash["parameters"]
        @irc.notice @client_sid, target, "[ERROR] The channel does not exist on this network."
        return
      end

      if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
        @irc.notice @client_sid, target, "[ERROR] You must be founder of #{hash["parameters"]} in order to remove Bot from the channel."
        return
      end

      if !is_channel_signedup hash["parameters"]
        @irc.notice @client_sid, target, "[ERROR] This channel is not signed up for Bot."
        return
      end

      remove_channel hash["parameters"]
      @irc.notice @client_sid, target, "[SUCCESS] Bot has left #{hash["parameters"]}."
      @irc.client_part_channel @client_sid, hash["parameters"]
      @irc.privmsg @client_sid, "#debug", "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})" if @irc.is_chan_founder hash["parameters"], target
      @irc.privmsg @client_sid, "#debug", "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)}) [OPER Override]" if @irc.is_oper_uid target
    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = c.Get
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000003"
    @initialized = false

    @e.on_event do |type, name, sock|
      if type == "IRCClientInit"
        config = @c.Get
        @irc = IRCLib.new name, sock, @config["connections"]["databases"]["test"]
        connect_client
        sleep 1
        join_channels
        @initialized = true
      end
    end

    @e.on_event do |type, hash|
      if type == "IRCChat"
        if !@initialized
          config = @c.Get
          @irc = IRCLib.new hash["name"], hash["sock"], config["connections"]["databases"]["test"]
          connect_client
          sleep 1
          join_channels
          @initialized = true
          sleep 1
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end
  end
end
