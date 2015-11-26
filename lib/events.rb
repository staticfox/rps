class Events

  def initialize
    @handlers = Hash.new if @handlers.nil?
    @pointers = Hash.new if @handlers.nil?
  end

  def Create event
    @handlers[event] = [] unless @handlers.has_key?(event)
    return true
  end

  def Remove file
    event = :event
    file = file[2..-1]
    if @handlers[event]
      count = 1
      @handlers[event].each do |block|
        @handlers[event].delete(block) if block.source_location[0].include?(file)
      end
    end
    count = nil
  end

  def DeleteEvent event
    @handlers.delete(event) if @handlers.has_key?(event)
  end

  def Signup event, block
    @handlers[event] = [] unless @handlers.has_key?(event)
    @handlers[event] << block
  end

  def on_event &block
    Signup(:event, block)
  end

  def Run *args
    event = :event
    if @handlers[event]
      @handlers[event].each { |block| block.call(*args) }
    end
    return true
  end

  def RunMod file, *args
    event = :event
    file = file[2..-1]
    if @handlers[event]
      @handlers[event].each do |block|
        block.call(*args) if block.source_location[0].include?(file)
      end
    end
    return true
  end

end # End Class "Events"
