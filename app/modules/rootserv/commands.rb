require "active_record"
require "chronic_duration"
require "date"

require_relative "../../libs/irc"

class RootservCommands

  @irc = nil

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def sendto_debug message
    @rs["debug_channels"].split(',').each { |x| @irc.privmsg @client_sid, x, message }
    @rs["control_channels"].split(',').each { |x| @irc.privmsg @client_sid, x, message }
  end

  def handle_svsnick hash
    target = hash["from"]
    return @irc.notice @client_sid, target, "User not specified" if hash["parameters"].empty?

    params = hash["parameters"].split(' ')

    if params[1].nil? or params[1].empty?
      return @irc.notice @client_sid, target, "New nickname not specified"
    else
      targetobj = @irc.get_nick_object params[0]
      return @irc.notice @client_sid, target, "Could not find user #{params[0]}" if !targetobj
      @irc.ts6_fnc @parameters["sid"], params[1], targetobj
      @irc.notice @client_sid, target, "Changed #{targetobj["Nick"]}'s nick to #{params[1]}"
      @irc.wallop @client_sid, "\x02#{@irc.get_nick_from_uid target}\x02 used \x02SVSNICK\x02 on \x02#{targetobj["Nick"]}\x02 => \x02#{params[1]}\x02"
    end
  end

  def handle_kill hash
    target = hash["from"]
    return @irc.notice @client_sid, target, "User not specified" if hash["parameters"].empty?

    params = hash["parameters"].split(' ')

    targetobj = @irc.get_nick_object params[0]
    sourceobj = @irc.get_uid_object @client_sid
    return @irc.notice @client_sid, target, "Could not find user #{params[0]}" if !targetobj

    if params.count == 1
      killmsg = "Requested"
    else
      killmsg = params[1..-1].join(' ')
    end

    @irc.kill sourceobj, targetobj["UID"], killmsg
    @irc.notice @client_sid, target, "Killed #{targetobj["Nick"]}"
    @irc.wallop @client_sid, "\x02#{@irc.get_nick_from_uid target}\x02 used \x02KILL\x02 on \x02#{targetobj["Nick"]}\x02"
  end

  def handle_whois hash
    target = hash["from"]
    return @irc.notice @client_sid, target, "User not specified" if hash["parameters"].empty?

    nick = hash["parameters"].split(' ')[0]
    targetobj = @irc.get_nick_object nick
    return @irc.notice @client_sid, target, "Could not find user #{nick}" if !targetobj

    @irc.notice @client_sid, target, "Information for \x02#{nick}\x02:"
    @irc.notice @client_sid, target, "UID: #{targetobj["UID"]}"
    @irc.notice @client_sid, target, "Signed on: #{DateTime.strptime(targetobj["CTime"], '%s').in_time_zone('America/New_York').strftime("%A %B %d %Y @ %l:%M %P %z")} (#{ChronicDuration.output(Time.new.to_i - targetobj["CTime"].to_i)} ago)"
    @irc.notice @client_sid, target, "Real nick!user@host: #{targetobj["Nick"]}!#{targetobj["Ident"]}@#{targetobj["Host"] == "*" ? targetobj["IP"] : targetobj["Host"]}"
    @irc.notice @client_sid, target, "Server: #{targetobj["Server"]}"
    @irc.notice @client_sid, target, "Services account: #{targetobj["NickServ"] == "*" ? "Not logged in." : targetobj["NickServ"]}"
    @irc.notice @client_sid, target, "User modes: #{targetobj["UModes"]}"
    @irc.notice @client_sid, target, "Channels: #{@irc.get_user_channels(targetobj["UID"]).join(' ')}"
    @irc.notice @client_sid, target, "End of whois information"
  end

  def handle_privmsg hash
    target = hash["from"]

    # Because of the ease of abuse, send *everything* to debug.
    sendto_debug "#{@irc.get_nick_from_uid target}: #{hash["command"]} #{hash["parameters"]}"

    case hash["command"].downcase
    when "help"
      # TODO
      if !hash["parameters"].empty?
        @irc.notice @client_sid, target, "***** #{@rs["nick"]} Help *****"
        @irc.notice @client_sid, target, "Extended help not implemented yet."
        @irc.notice @client_sid, target, "***** End of Help *****"
        return
      end

      @irc.notice @client_sid, target, "***** #{@rs["nick"]} Help *****"
      @irc.notice @client_sid, target, "#{@rs["nick"]} allows for extra control over the network. This is intended for debug use only. i.e. don't abuse #{@rs["nick"]}."
      @irc.notice @client_sid, target, "For more information on a command, type \x02/msg #{@rs["nick"]} help <command>\x02."
      @irc.notice @client_sid, target, "The following commands are available:"
      @irc.notice @client_sid, target, "KILL <nick> [message]       Kills a client"
      @irc.notice @client_sid, target, "SVSNICK <nick> <newnick>    Changes nick's name to newnick"
      @irc.notice @client_sid, target, "WHOIS <nick>                Returns information on the nick"
      @irc.notice @client_sid, target, "***** End of Help *****"

    when "svsnick"
      handle_svsnick hash

    when "kill"
      handle_kill hash

    when "whois"
      handle_whois hash

    else
      @irc.notice @client_sid, target, "#{hash["command"].upcase} is an unknown command."

    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = c.Get
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000004"
    @initialized = false

    @e.on_event do |type, hash|
      if type == "Rootserv-Chat"
        if !@initialized
          @config = @c.Get
          @rs = @config["rootserv"]
          @irc = IRCLib.new hash["name"], hash["sock"], @config["connections"]["databases"]["test"]
          @initialized = true
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end
  end

end
