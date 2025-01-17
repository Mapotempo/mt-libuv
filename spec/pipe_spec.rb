require 'mt-libuv'


describe MTLibuv::Pipe do
	before :each do
		@log = []
		@general_failure = []

		@reactor = MTLibuv::Reactor.new
		@server = @reactor.pipe
		@client = @reactor.pipe
		@timeout = @reactor.timer do
			@reactor.stop
			@general_failure << "test timed out"
		end
		@timeout.start(5000)

		@pipefile = "/tmp/test-pipes.pipe"

		@reactor.all(@server, @client, @timeout).catch do |reason|
			@general_failure << reason.inspect
			@general_failure << "Failed with: #{reason.message}\n#{reason.backtrace}\n"
		end

		@reactor.notifier do |error, context|
			begin
				@general_failure << "Log called: #{context}\n#{error.message}\n#{error.backtrace.join("\n") if error.backtrace}\n"
			rescue Exception => e
				@general_failure << "error in logger #{e.inspect}"
			end
		end

		begin
			File.unlink(@pipefile)
		rescue
		end
	end

	after :each do
		begin
			File.unlink(@pipefile)
		rescue
		end
	end
	
	describe 'bidirectional inter process communication' do

		it "should send a ping and return a pong" do
			@reactor.run { |reactor|
				@server.bind(@pipefile) do |client|
					client.progress do |data|
						@log << data
						client.write('pong')
					end
					client.start_read
				end

				# catch server errors
				@server.catch do |reason|
					@general_failure << reason.inspect
					@reactor.stop

					@general_failure << "Failed with: #{reason.message}\n#{reason.backtrace}\n"
				end

				# start listening
				@server.listen(1024)



				# connect client to server
				@client.connect(@pipefile) do |client|
					@client.progress do |data|
						@log << data

						@client.close
					end

					@client.start_read
					@client.write('ping')
				end

				@client.catch do |reason|
					@general_failure << reason.inspect
					@reactor.stop

					@general_failure << "Failed with: #{reason.message}\n#{reason.backtrace}\n"
				end

				# Stop the reactor once the client handle is closed
				@client.finally do
					@server.close
					@reactor.stop
				end
			}

			expect(@general_failure).to eq([])
			expect(@log).to eq(['ping', 'pong'])
		end
	end

	# This test won't pass on windows as pipes don't work like this on windows
	describe 'unidirectional pipeline', :unix_only => true do
		before :each do
			system "/usr/bin/mkfifo", @pipefile
		end

		it "should send work to a consumer" do
			@reactor.run { |reactor|
				heartbeat = @reactor.timer
				@file1 = @reactor.file(@pipefile, File::RDWR|File::NONBLOCK) do
					@server.open(@file1.fileno) do |server|
						heartbeat.progress  do
							@server.write('workload').catch do |err|
								@general_failure << err
							end
						end
						heartbeat.start(0, 200)
					end
				end
				@file1.catch do |e|
					@general_failure << "Log called: #{e.inspect} - #{e.message}\n"
				end

				@file2 = @reactor.file(@pipefile, File::RDWR|File::NONBLOCK) do
					# connect client to server
					@client.open(@file2.fileno) do |consumer|
						consumer.progress do |data|
							@log = data
						end

						consumer.start_read
					end
				end


				timeout = @reactor.timer do
					@server.close
					@client.close
					timeout.close
					heartbeat.close
					@reactor.stop
				end
				timeout.start(1000)
			}

			expect(@general_failure).to eq([])
			expect(@log).to eq('workload')
		end
	end
end
