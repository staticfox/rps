module Match
  def self.match template, tomatch, ignorecase
    return Regexp.new("^#{Regexp.escape(template).gsub('\*','.*?').gsub('\?', '.?')}$", ignorecase) =~ tomatch
  end
end
