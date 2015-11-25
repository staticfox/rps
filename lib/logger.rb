class Logger

  @logger = Logger.new('../logs/project.log', 'daily')

  def LogToConsole string
    puts string
  end

  def LogToSTDERR string
    STDERR.puts string
  end

  def LogToFile file, string
  end

end # End Class "Logger"
