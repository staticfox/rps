require "active_record"

require_relative "../../libs/irc"
require_relative "flags"

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

  def is_channel_signed_up input
    @assigned_channels.each { |x|
      return true if input.downcase == x["channel"].downcase
    }
    return false
  end

  def get_channel_flags input
    @assigned_channels.each { |x|
      return x["flags"] if input.downcase == x["channel"].downcase
    }
    return false
  end

  def connect_client
    joined = []
    @irc.add_client @parameters["sid"], @client_sid, @parameters["server_name"], @bot["nick"], @bot["modes"], @bot["user"], @bot["host"], @bot["real"]
    # FIXME zip arrays?
    @bot["idle_channels"].split(',').each { |i|
      next if joined.include? i or is_channel_signed_up i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@bot["nick"]}"
    }
    @bot["debug_channels"].split(',').each { |i|
      next if joined.include? i or is_channel_signed_up i; joined << i
      @irc.client_join_channel @client_sid, i
      @irc.client_set_mode @client_sid, "#{i} +o #{@bot["nick"]}"
    }
    @bot["control_channels"].split(',').each { |i|
      next if joined.include? i or is_channel_signed_up i; joined << i
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
    hash = {"channel" => channel.downcase, "flags" => Flags::All}
    @assigned_channels << hash
  end

  def remove_channel channel
    BotChannel.establish_connection(@db)
    query = BotChannel.where(channel: channel.downcase)
    query.delete_all
    BotChannel.connection.disconnect!
    @assigned_channels.delete_if { |h| h["channel"] == channel.downcase }
    return
  end

  def join_channels
    BotChannel.establish_connection(@db)
    queries = BotChannel.all
    return if queries.count == 0
    queries.each do |query|
      if query.options.nil?
        setflags = Flags::All
      else
        setflags = query.options
      end
      hash = {"channel" => query.channel, "flags" => setflags}
      @assigned_channels << hash
      sendto_debug "JOINED: #{query.channel}"
      next if @irc.is_user_in_channel @client_sid, query.channel
      @irc.client_join_channel @client_sid, query.channel
      @irc.client_set_mode @client_sid, "#{query.channel} +o #{@client_sid}"
    end
    BotChannel.connection.disconnect!
  end

  def edit_flags target, hash
    sparms = hash["parameters"].split(' ')

    if sparms.count < 1
      me_user_notice target, "SET requires more parameters"
      return
    end

    channel = sparms[0]
    if !@irc.does_channel_exist channel
      me_user_notice target, "That channel does not exist on this network."
      return
    end

    if !@irc.is_chan_founder channel, target and
      !@irc.is_chan_admin    channel, target and
      !@irc.is_chan_op       channel, target and
      !@irc.is_oper_uid target # Bot ACLs?
        me_user_notice target, "You need atleast op access in #{channel} to use SET"
        return
    end

    if !is_channel_signed_up channel
      me_user_notice target, "This channel is not signed up for #{@bot["nick"]}"
      return
    end

    flags = get_channel_flags channel

    if sparms.count == 1
      me_user_notice target, "Options for \x02#{channel}\x02:"
      me_user_notice target, " "
      me_user_notice target, "Google:       #{((flags & Flags::Google) > 0)     ? "On" : "Off"}"
      me_user_notice target, "Calculator:   #{((flags & Flags::Calculator) > 0) ? "On" : "Off"}"
      me_user_notice target, "Quotes:       #{((flags & Flags::Quotes) > 0)     ? "On" : "Off"}"
      me_user_notice target, "Weather:      #{((flags & Flags::Weather) > 0)    ? "On" : "Off"}"
      me_user_notice target, " "
      me_user_notice target, "End of options for #{channel}"
    elsif sparms.count == 2
      case sparms[1].downcase
      when 'google'
        me_user_notice target, "Google is set to \x02#{((flags & Flags::Google) > 0) ? "On" : "Off"}\x02 for \x02#{channel}\x02."
      when 'quotes'
        me_user_notice target, "Quotes is set to \x02#{((flags & Flags::Quotes) > 0) ? "On" : "Off"}\x02 for \x02#{channel}\x02."
      when 'calc', 'calculator'
        me_user_notice target, "Calculator is set to \x02#{((flags & Flags::Calculator) > 0) ? "On" : "Off"}\x02 for \x02#{channel}\x02."
      when 'weather'
        me_user_notice target, "Weather is set to \x02#{((flags & Flags::Weather) > 0) ? "On" : "Off"}\x02 for \x02#{channel}\x02."
      else
        me_user_notice target, "#{sparms[1]} is an unknown option."
      end
    elsif sparms.count > 2
      option  = sparms[1]
      value   = sparms[2]

      to_set = false
      flag_to_set = ''

      case value.downcase
      when '0'
        to_set = false
      when 'off'
        to_set = false
      when '1'
        to_set = true
      when 'on'
        to_set = true
      else
        me_user_notice target, "#{value} is not a valid option. (On or Off)"
        return
      end

      case option.downcase
      when 'google'
        set_flag channel, flags, Flags::Google, to_set, target
      when 'quotes'
        set_flag channel, flags, Flags::Quotes, to_set, target
      when 'calc', 'calculator'
        set_flag channel, flags, Flags::Calculator, to_set, target
      when 'weather'
        set_flag channel, flags, Flags::Weather, to_set, target
      else
        me_user_notice target, "#{option} is an unknown option"
      end
    end

  end

  def set_flag channel, current_flags, flag, to_set, target
    BotChannel.establish_connection(@db)
    conf = BotChannel.find_by(channel: channel.downcase)
    has_flag = (flag & current_flags > 0)

    take_action = false

    if has_flag && !to_set
      newflags = current_flags - flag
      take_action = true
    elsif !has_flag and to_set
      newflags = current_flags + flag
      take_action = true
    end

    if take_action
      conf.update(options: newflags)
      @assigned_channels.delete_if { |h| h["channel"] == channel.downcase }
      @assigned_channels << {"channel" => channel.downcase, "flags" => newflags}
      me_user_notice target, "Flags set on #{channel}."
    else
      me_user_notice target, "That flag is already set."
    end

    BotChannel.connection.disconnect!
  end

  def shutdown message
    @irc.remove_client @client_sid, message
  end

  def handle_privmsg hash

    if is_channel_signed_up hash["target"].downcase
      @e.Run "Bot-Chat", hash, get_channel_flags(hash["target"].downcase)
      return
    end

    target = hash["target"]
    target = hash["from"] if target == @client_sid

    return if hash["target"] != @client_sid

    # I'll change this later, it's 4 a.m. and I'm tired.
    sendto_debug "#{@irc.get_nick_from_uid target}: #{hash["command"]} #{hash["parameters"]}"

    case hash["command"].downcase
    when "help"
      me_user_notice target, "***** \x02#{@bot["nick"]} Help\x02 *****"
      if !hash["parameters"].empty?
        subcommands = hash["parameters"].split(' ')
        case subcommands[0].downcase
        when "request"
          me_user_notice target, "Help for \x02#{subcommands[0].upcase}\x02:"
          me_user_notice target, " "
          me_user_notice target, "\x02#{subcommands[0].upcase}\x02 allows you to register a channel with"
          me_user_notice target, "#{@bot["nick"]} so you and your users can enjoy #{@bot["nick"]}'s features."
          me_user_notice target, " "
          me_user_notice target, "Syntax: REQUEST <#channel>"
          me_user_notice target, " "
          me_user_notice target, "Examples:"
          me_user_notice target, "    /msg #{@bot["nick"]} REQUEST #rps"
          me_user_notice target, "***** \x02End of Help\x02 *****"
          return

        when "remove"
          me_user_notice target, "Help for \x02#{subcommands[0].upcase}\x02:"
          me_user_notice target, " "
          me_user_notice target, "\x02#{subcommands[0].upcase}\x02 allows you to unregister a channel."
          me_user_notice target, " "
          me_user_notice target, "Once you REMOVE a channel, all of the data"
          me_user_notice target, "associated with it are removed and cannot"
          me_user_notice target, "be restored."
          me_user_notice target, " "
          me_user_notice target, "Syntax: REMOVE <#channel>"
          me_user_notice target, " "
          me_user_notice target, "Examples:"
          me_user_notice target, "    /msg #{@bot["nick"]} REMOVE #rps"
          me_user_notice target, "***** \x02End of Help\x02 *****"
          return

        when "set"
          if subcommands[1]
            me_user_notice target, "Extended help not implemented yet."
            me_user_notice target, "***** \x02End of Help\x02 *****"
            return
          end
          me_user_notice target, "Help for \x02#{subcommands[0].upcase}\x02:"
          me_user_notice target, " "
          me_user_notice target, "\x02#{subcommands[0].upcase}\x02 allows you to set various control options"
          me_user_notice target, "for channel that changes the way #{@bot["nick"]} interacts"
          me_user_notice target, "with your channel."
          me_user_notice target, " "
          me_user_notice target, "The following subcommands are available:"
          me_user_notice target, " "
          me_user_notice target, "Syntax: SET <#channel> <option> <on|off>"
          me_user_notice target, " "
          me_user_notice target, "Examples:"
          me_user_notice target, "    /msg #{@bot["nick"]} SET #rps quotes on"
          me_user_notice target, "***** \x02End of Help\x02 *****"
          return

        else
          me_user_notice target, "No help available for \x02#{subcommands[0].downcase}\x02."
          me_user_notice target, "Help dialogs are still a work in progress."
          me_user_notice target, "If you're having trouble or you need additional help, you may want to join the help channel #help."
          return
        end
      end

      me_user_notice target, "#{@bot["nick"]} is a utility bot that adds functionality to your channel."
      me_user_notice target, "The following commands are available:"
      me_user_notice target, "REQUEST                   Request #{@bot["nick"]} for your channel."
      me_user_notice target, "REMOVE                    Remove #{@bot["nick"]} from your channel."
      me_user_notice target, "SET <#channel>            Sets specific options for your channel."
      me_user_notice target, "***** In Channel Commands *****"
      me_user_notice target, "!w <zip/city, state>      Displays the current weather conditions."
      me_user_notice target, "!g <google search>        Searches google for what you specified."
      me_user_notice target, "!q                        Displays a random quote from your channel."
      me_user_notice target, "!q <add>                  Adds a quote."
      me_user_notice target, "!q <del> <number>         Delete (number)'s quote from the databases."
      me_user_notice target, "\x02NOTE\x02 !q is an alias of !quote, !w is an alias of !weather, !g is an alias of !google"
      me_user_notice target, "***** \x02End of Help\x02 *****"
      me_user_notice target, "If you're having trouble or you need additional help, you may want to join the help channel #help."

    when "request"
      return me_user_notice target, "[ERROR] No channel was specified." if hash["parameters"].empty?
      return me_user_notice target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return me_user_notice target, "[ERROR] You must be founder of #{hash["parameters"]} in order to add #{@bot["nick"]} to the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return me_user_notice target, "[ERROR] This channel is already signed up for #{@bot["nick"]}." if is_channel_signed_up hash["parameters"]
      signup_channel hash["parameters"]
      me_user_notice target, "[SUCCESS] #{@bot["nick"]} has joined #{hash["parameters"]}."
      @irc.client_join_channel @client_sid, hash["parameters"]
      @irc.client_set_mode @client_sid, "#{hash["parameters"]} +o #{@client_sid}"
      sendto_debug "REQUEST: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"

    when "remove"
      return me_user_notice target, "[ERROR] No channel was specified." if hash["parameters"].empty?
      return me_user_notice target, "[ERROR] The channel does not exist on this network." if !@irc.does_channel_exist hash["parameters"]
      return me_user_notice target, "[ERROR] You must be founder of #{hash["parameters"]} in order to remove #{@bot["nick"]} from the channel." if !@irc.is_chan_founder hash["parameters"], target and !@irc.is_oper_uid target
      return me_user_notice target, "[ERROR] This channel is not signed up for #{@bot["nick"]}." if !is_channel_signed_up hash["parameters"]

      remove_channel hash["parameters"]
      me_user_notice target, "[SUCCESS] #{@bot["nick"]} has left #{hash["parameters"]}."
      @irc.client_part_channel @client_sid, hash["parameters"], "#{@irc.get_nick_from_uid(@client_sid)} removed by #{@irc.get_nick_from_uid(target)}"
      sendto_debug "REMOVED: #{hash["parameters"]} - (#{@irc.get_nick_from_uid(target)})#{"[OPER Override]" if @irc.is_oper_uid target and !@irc.is_chan_founder hash["parameters"], target}"

    when "set"
      return me_user_notice target, "[ERROR] No channel was specified." if hash["parameters"].empty?
      edit_flags target, hash
      return

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
        @irc = IRCLib.new name, sock
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
          @irc = IRCLib.new hash["name"], hash["sock"]
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
