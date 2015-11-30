require "mechanize"
require "google-search"
require "erb"

include ERB::Util

require_relative "../libs/irc"

class BotG

  def send_data name, sock, string
    time = Time.now
    puts "[~S] [#{name}] [#{time.strftime("%Y-%m-%d %H:%M:%S")}] #{string}"
    sock.send string, 0
  end

  def gc parameters
    begin
      doc = Mechanize.new.get("http://173.194.115.72/search?q=#{url_encode(parameters)}")
      result = doc.search("//h2[@class='r']").inner_text
    rescue StandardError => e
      @irc.privmsg @client_sid, @config["debug-channels"]["bot"], "[ERROR] #{__method__.to_s}: #{e.message}"
      return "An unexpected error has occured. The developers have been notified."
    end
    return "No Result Found." if result.empty?
    return result
  end

  def gs parameters
    begin
      data = Google::Search::Web.new(:query => url_encode(parameters))
      array = []
      data.each { |result| array.push(result) }
    rescue StandardError => e
      @irc.privmsg @client_sid, @config["debug-channels"]["bot"], "[ERROR] #{__method__.to_s}: #{e.message}"
      return "An unexpected error has occured. The developers have been notified."
    end
    return "#{array[0].title} - #{array[0].uri}" if array[0]
    return "No Result Found."
  end

  def handle_privmsg hash
    target = hash["target"]
    target = hash["from"] if target == @client_sid

    return if !['#', '&'].include? target[0]

    # FIXME
    if hash["parameters"].empty? and ["!calc", "!g", "!google"].include? hash["command"].downcase
      @irc.notice @client_sid, hash["from"], "#{hash["command"][1..-1]} requires more parameters"
      return
    end

    case hash["command"].downcase
    when "!calc"
      @irc.privmsg @client_sid, target, "Google Calculator: #{gc(hash["parameters"])}"
    when "!g", "!google"
      @irc.privmsg @client_sid, target, "Google Search: #{gs(hash["parameters"])}"
    end
  end

  def init e, m, c, d
    @e = e
    @m = m
    @c = c
    @d = d

    @config = @c.Get
    @parameters = @config["connections"]["clients"]["irc"]["parameters"]
    @client_sid = "#{@parameters["sid"]}000003"
    @initialized = false

    @e.on_event do |type, hash|
      if type == "Bot-Chat"
        if !@initialized
          @config = @c.Get
          @irc = IRCLib.new hash["name"], hash["sock"], @config["connections"]["databases"]["test"]
          @initialized = true
        end
        handle_privmsg hash if hash["msgtype"] == "PRIVMSG"
      end
    end
  end
end
