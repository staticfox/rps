require 'active_record'

class DB

	def initialize e
		@e = e
		@debug = true
		@Connections = []
	end

	def Create name, hash
		begin
			ActiveRecord::Base.establish_connection(hash)
			client = ActiveRecord::Base.connection
			hash = {"name" => name, "sock" => client}
			@Connections.push(hash)
		rescue => e
			puts e.message
		end
	end

	def GetConnections
		return @Connections
	end

	def GetConnection name
		@Connections.each do |hash|
			return hash["sock"] if hash["name"] == name
		end
	end	

end # End Class "DB"
