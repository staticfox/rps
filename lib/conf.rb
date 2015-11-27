require "yaml"

class Configuration

  def Save newconfig
    begin
      File.open('../cfg/config.yaml','w') do |cf|
        cf.write $newconfig.to_yaml
      end
    rescue => e
      puts e.message
    end
  end

  def Get
    begin
      data = YAML.load_file("../cfg/config.yaml")
      if defined?(data)
        return data
      else
        return false
      end
    rescue => e
      puts e.message
    end
  end

end # End Class "Configuration"
