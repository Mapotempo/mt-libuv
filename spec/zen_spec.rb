require 'mt-libuv'


describe MTLibuv::Listener do
	it "should ensure there are no remaining object references in callbacks", network: true do
		require 'objspace'

		checked = []

		# These are created by loop objects and are never cleaned up
		# This is OK as the loops are expected to execute for the life of the application
		except = [::MTLibuv::Async, ::MTLibuv::Timer, ::MTLibuv::Prepare, ::MTLibuv::Signal]

		ObjectSpace.each_object(Class) do |cls|
			next unless cls.ancestors.include? ::MTLibuv::Handle
			next if checked.include? cls
			checked << cls

			values = cls.callback_lookup.values
			values.select! {|val| except.include?(val.class) ? false : val.class }

			if values.length > 0
				puts "\nMemory Leak in #{cls} with #{values.length} left over objects"
				puts "Checked #{checked.length} classes, objects are:"
				values.each do |val|
					puts "\n#{val}\n"
				end
				raise 'Free the machines!'
			end
		end

		expect(checked.length).to be > 3
	end
end
