class Modules

	$classsloaded = []
	$totalmodules = []

	def LoadByNameOfFile file, classtitle

		begin
			puts "Loading - #{file} - #{classtitle}"
			load file if File.file?(file)
			
			newmod = Object.const_get(classtitle).new
			newmod.init @e, self, @c, @d

			newclass = [newmod.class.name => newmod]
			newmodule = {"filename" => file, "classtitle" => classtitle}
			$totalmodules.push(newmodule)
			$classsloaded.push(newclass)
			newclass = nil
			newmodile = nil
			puts "Loaded - #{file} - #{classtitle}"
			return true
		rescue => e
			puts e.message
			return false
		end
	end


	def UnloadByClassName classname
		count = 1
		$classsloaded.each do |output|
        		output.each do |classtitle|
               			classtitle.each do |classthing, theclass|
					if classname == classthing then
						$classsloaded.delete_at(count)
						$classsloaded.delete(output)
						$totalmodules.each do |amodule|
							@e.Remove amodule["filename"] if amodule["classtitle"] == classname 
						end
						return true
					else
                       				count += 1
					end
               			end
        		end
		end
		return false
        end

	def ReloadByClassName file, classtitle
		UnloadByClassName classtitle
		LoadByNameOfFile file, classtitle
	end

	def ListLoaded
		return $classsloaded if $classsloaded.count >= 1
		return false if $classsloaded.count == 0
	end

	def GetModuleByClassName classname
		$classsloaded.each do |output|
                        output.each do |classtitle|
                                classtitle.each do |classthing, theclass|
					return theclass if classname == classthing
                                end
                        end
                end
		return false
	end

	def initialize e, c, d
		@e = e
		@c = c
		@d = d
	end

end # End Class "Modules"
