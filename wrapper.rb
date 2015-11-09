puts "Starting up, please wait..."

# check for arguments passed in
@exit_due_to_network = false
@arguments_passed = false
unless ARGV[0].nil?
	if ARGV[0].downcase.strip == 'network'
		@exit_due_to_network = true
	else
		puts "Password argument was provided | Running in test mode"
		@arguments_passed = true
		@arg_password = ARGV[0].strip
	end
end

# load libraries
require (File.expand_path(File.dirname(__FILE__))) + '/library.rb'

# exit if the ocra executable was run from a network drive
exit_application('network') if @exit_due_to_network

# main application logic
begin
	spinner_start

	# exit if execution is part of build process
	if Object.const_defined?(:Ocra)
		spinner_stop
		puts "Exiting wrapper.rb during OCRA build process".yellow
		exit
	end

	# generate current run info
	app_start = Time.now
	current_time = Time.now.strftime("%Y%m%d%H%M%S")
	@current_computer = ENV["COMPUTERNAME"]
	current_user = ENV['USERNAME']
	log_counter = 1
	@username = 'qatester1'
	build_history = File.read(File.expand_path(File.dirname(__FILE__)) + '/build_history.txt')
	build_date, build_info = build_history.split("\n").last.split(' | ')
	latest_build_on_network = File.readlines('//mir/qa/Automation/Utilities/SVN_Remote_Updater/build_history.txt').last.split(' | ').first
	@logfile = './Output_' + current_time + '.txt'
	paexec_log = File.absolute_path("./PAExecLog_#{Time.now.strftime("%Y%m%d-%H%M%S")}.txt")

	# move the window
	`mode con:cols=80 lines=1000`
	position_console unless ENV["OCRA_EXECUTABLE"].nil?

	# notate run log
	unless ENV['OCRA_EXECUTABLE'].nil?
		Dir.mkdir('//mir/QA/temp') unless Dir.exist?('//mir/QA/temp')
		run_log = '//mir/QA/temp/SVN_Remote_Updater_run_log.txt'
		message = "#{Time.now} | New run detected with following info:\n\tUser:      #{ENV['USERNAME']}\n\tComputer:  #{ENV['COMPUTERNAME']}\n\tLocation:  #{ENV['OCRA_EXECUTABLE']}\n\tLogfile:   #{File.absolute_path(@logfile)}\n\tVersion:   #{build_info}\n\tBuildDate: #{build_date}\n"
		File.open(run_log, 'a'){ |f| f.puts message}
	end

	# verify/create remote log folder
	Dir.mkdir("#{@remote_log_folder}/#{current_user}") unless Dir.exist?("#{@remote_log_folder}/#{current_user}")

	# rename SVN authentication folder
	@reset_auth = false
	auth_files = Dir.glob(@auth_directory)
	unless auth_files.empty?
		@reset_auth = true
		auth_files.each do |f|
			current_path = File.absolute_path(f)
			next if current_path.include?('_backup')
			new_path = current_path + '_backup'
			FileUtils.mv(current_path, new_path)
		end
	end

	# record start of app in local log
	append_log("\n\n#{Time.now} | Application start")
	append_log("\n#{Time.now} | Using build: #{build_info}")

	# start user interaction
	spinner_stop
	append_log("\n********************************************************************\n********************************************************************\n#{Time.now} | Starting user interaction")
	clearscreen
	unless @arguments_passed
		message = []
		message << "\n====================\nSVN Remote Updater\n====================\n".green
		message << "Created by".ljust(25, '.') + " Damien Storm ".yellow
		message << "Current time".ljust(25, '.') + " #{Time.now}".yellow
		message << "Current build".ljust(25, '.') + " #{build_info}".yellow
		message << "Current build date".ljust(25, '.') + " #{build_date}".yellow
		if (Time.parse(latest_build_on_network) - Time.parse(build_date)) > 0
		# if (Time.parse(build_date) - Time.parse(latest_build_on_network)) > 0
			message << "Latest available build".ljust(25, '.') + " #{latest_build_on_network}".red
			message << "\n=============================================================================".red
			message << "There is an updated version of this software available on the network!".red
			message << "\n=============================================================================".red
			message << "\nPlease copy the updated version of the application to your computer from the  network location below, and run the updated version of the application.".yellow
			message << "\n\\\\mir\\qa\\Automation\\Utilities\\SVN_Remote_Updater\\SVN_Remote_Updater.exe".green
			message << "\nFor questions or concerns, please contact:"
			message << "Damien Storm | damisto@cdw.com | damien.storm@orasi.com".cyan
			message << "\nPress ".green + "enter".blue + " to exit...".green
			puts message.join("\n")
			STDIN.gets.chomp
			exit_application
		end
		message << "Latest available build".ljust(25, '.') + " #{latest_build_on_network}".green
		message << "\n===================="
		message << "For questions or concerns, please contact:"
		message << "Damien Storm | damisto@cdw.com | damien.storm@orasi.com".cyan
		message << "\n===================="
		message << "If you need to exit the program, please press Ctrl+C on the keyboard.".red
		message << "===================="
		message << "Press ".green + "enter".blue + " to continue...".green
		puts message.join("\n")
		STDIN.gets.chomp
	end

	# verify user has command-line version of SVN installed
	installed = verify_svn_install
	unless installed
		wrap '<<<<< ATTENTION!!! >>>>>'.cyan
		append_log("\n#{Time.now} | TortoiseSVN and/or the command line module are not installed. Prompting user for installation.")
		wrap "This computer does not have the command line module of TortoiseSVN installed. This module is necessary for this application to continue."
		wrap "To update your installation of TortoiseSVN to the latest version and add the command line module, type 'Y' and press enter. Type anything else and press enter to exit this application".yellow
		if STDIN.gets.chomp.downcase == 'y'
			append_log("#{Time.now} | User chose to install the latest version of TortoiseSVN.")
			result = kill_processes('svn')
			if result
				result = install_svn
			end
		else
			exit_application
		end

		if result
			wrap "Successfully installed the latest version of TortoiseSVN and the command line module. The application can now continue".green
			wrap "Press any key to continue"
			STDIN.gets.chomp
		else
			wrap "There was an issue installing the latest version of TortoiseSVN and the command line module. Please check the output log for more details.".red
			wrap "Press any key to exit the application"
			STDIN.gets.chomp
			exit_application
		end
	end

	# display warning get qatester1 password
	if @arguments_passed
		@password = @arg_password
		@credentials = "--username #{@username} --password #{@password} "
	else
		show_warning_and_get_password
	end

	loop do
		@output = []
		@success = true
		log_info = "#{current_time}-#{log_counter}_#{current_user}"
		pattern = "#{@remote_log_folder}/#{current_user}/*#{log_info}*.txt"
		@computers_selected = nil
		@command_selected = nil
		@branch_different = false

		# computer group selection
		if @arguments_passed
			@computers_selected = @computer_groups[:Testing].split(',')
		else
			@computers_selected = select_computer_group
		end
		total_computers = @computers_selected.count

		# command selection
		if @arguments_passed
			@command_selected = [100, "testing"]
		else
			@command_selected = select_command
		end

		# choose branch or tag if needed
		@command_selected.first.to_i == 4 ? select_branch_or_tag : @branch = '/Trunk/AutoSource_Prod'

		# command verification
		unless @arguments_passed
			result = verify_command(@command_selected.to_s)
			if result == 'restart'
				append_log("\n#{Time.now} | User chose to restart application")
				next
			end
		end

		# command processing
		command_start = Time.now
		clearscreen
		wrap "<<<<< COMMAND PROCESSING >>>>>".yellow

		complete_command = %Q|#{@paexec_location} \\\\REMOTE_COMPUTER -d -u corp.cdw.com\\#{@username} -p #{@password} -lo #{paexec_log} -c -f -csrc "#{@remote_location}" remote.exe #{@command_selected.first} #{log_info} #{@username} #{@password} #{@branch}|

		append_log("\n\n#{Time.now} | Command to be sent to remote computers:\n\t #{complete_command}")

		puts "Executing command:\n#{@command_selected.last.to_s.yellow}"
		puts "\nOn #{total_computers.to_s.yellow} computers:"
		puts print_computers(@computers_selected)
		puts "\nWith this username | pwd:"
		puts "#{@username} | #{@password}".yellow
		puts "\nVia the following remote command:"
		puts complete_command.yellow

		# run the main command and start monitoring the paexec output
		puts "\n=================================================="
		wrap "Distributing remote command to #{total_computers} computers. Please wait until the process is complete.".green
		puts "==================================================\n"
		@successful = 0
		@failed = 0
		status_display = Thread.new {
			loop do
				['|', '/', '-', '\\'].each do |c|
					message = "#{get_percent_complete(@successful + @failed, total_computers)}".cyan + " | Successful: " + @successful.to_s.green + " | Failed: " + @failed.to_s.red
					print "\r#{c}  #{message}   "
					sleep 0.1
				end
			end
		}
		threads = []
		results = {}
		no_response = []
		@computers_selected.each do |c|
			threads << Thread.new do
				unique_command = complete_command.sub(paexec_log, paexec_log.sub('.txt', "_#{c}.txt")).sub('REMOTE_COMPUTER', c)
				results.store(c.to_sym, execute_command(unique_command))
			end
		end
		wait_timer = Time.now
		wait_counter = 0
		completed_computers = []
		loop do
			results.each do |k,v|
				unless completed_computers.include? k.to_s
					if v.first
						@successful += 1
					else
						@failed += 1
					end
					completed_computers.push k.to_s
				end
			end
			break if results.count == total_computers
			if Time.now - wait_timer > 60*5
				no_response = @computers_selected - results.keys.join(' ').to_s.split(' ')
				@success = false
				status_display.kill
				message = "Distribution of command to remote computers has now taken over 5 minutes and will halt. The following computers have not responded and may need to be manually checked for issues:\n".red + print_computers(no_response)
				append_log("\n#{Time.now} | #{message}")
				wrap(message)
				break
			end
			sleep 0.25
			wait_counter += 0.25
		end
		log_contents = ''
		Dir.glob("./#{File.basename(paexec_log, '.txt')}*").each do |log|
			computer = File.basename(log, '.txt').split('_').last.to_sym
			results[computer].push(File.read(log))
			log_contents << File.read(log)
			File.delete(log)
		end
		failed_computers = []
		results.each do |k, v|
			unless v.first
				append_log("Execution of remote command failed on [#{k.to_s.yellow}] with the following error:\n\t#{v.last.red}")
				failed_computers << k.to_s
			end
		end
		sleep 2
		status_display.kill
		puts "\n=================================================="
		if failed_computers.count == 0
			append_log("\n\n#{Time.now} | Remote command was successfully distributed to all #{total_computers} computers. PAExec log content was:")
			append_log(log_contents)
			wrap "Remote command was successfully distributed to all #{total_computers} computers!".green
		else
			append_log("\n\n#{Time.now} | Distribution of command encountered errors on #{failed_computers.count} of #{total_computers} computers.")
			wrap "Distribution of command encountered errors on #{failed_computers.count} of #{total_computers} computers. The following computers reported errors: ".red
			puts print_computers(failed_computers)
			if failed_computers.count == total_computers
				wrap "Distribution of the command failed on all computers. Please see the output log for details. The application will now exit.".red
				exit_application
			else
				wrap "Please see output log for more details. Execution will now continue on the remaining #{total_computers - failed_computers.count} computers.".yellow
			end
		end

		remaining_computers = total_computers - failed_computers.count
		puts "\n=================================================="
		wrap "Depending upon the command you selected, execution could take several minutes.".light_magenta
		wrap "Please wait until the application notifies you that execution is complete. The application will automatically timeout after 5 minutes.".light_magenta
		puts "==================================================\n"
		# start watching for remote log files
		loop_start = Time.now
		processed_logs = Array.new
		# spinner_start
		@successful = 0
		@failed = 0
		status_display = Thread.new {
			loop do
				['|', '/', '-', '\\'].each do |c|
					message = "#{get_percent_complete(@successful + @failed, remaining_computers)}".cyan + " | Successful: " + @successful.to_s.green + " | Failed: " + @failed.to_s.red
					print "\r#{c}  #{message}   "
					sleep 0.1
				end
			end
		}
		loop do
			# get all the remote log files
			all_logs = Dir.glob(pattern)
			unproccessed_logs = all_logs - processed_logs

			# process files that are complete
			unless unproccessed_logs.empty?
				unproccessed_logs.each do |log|
					contents = File.read(log)
					marker = "=====|||||====="
					if contents.include?(marker)
						contents.split(marker).last.split("\n").each{ |o| @output.push o}
						processed_logs.push log
						contents.split("\n").reverse.each do |l|
							if l.include?('<<<<<')
								if l.include?('failed')
									@success = false
									contents.split("\n").each { |e| puts "\t#{e}".red if e.include?('-----')}
									@failed += 1
								else
									@successful += 1
								end
								break
							end
						end
					end
				end
			end

			if all_logs.count == remaining_computers && unproccessed_logs.count == 0
				sleep 2
				status_display.kill
				wrap "Command execution has completed on #{all_logs.count} computers.".yellow
				break
			end

			if Time.now - loop_start > 60*5
			# if Time.now - loop_start > 60*1
				@success = false
				status_display.kill
				message = "Command execution has now taken over 5 minutes and will halt. Some computers may need to be manually checked for issues."
				append_log("\n#{Time.now} | #{message}")
				wrap(message.red)
				break
			end
			sleep 0.5
		end
		sleep 2
		status_display.kill

		# add contents of remote logs to the local logfile
		File.open(@logfile, 'a') do |f|
			Dir.glob(pattern).each { |l| f.puts File.read(l)}
		end

		# add contents of @output to the local logfile
		File.open(@logfile, 'a') do |f|
			@output.each { |o| f.puts o}
		end

		spinner_stop
		puts "\n==================================================".blue
		wrap "<<<<< PROCESSING COMPLETE >>>>>".yellow

		# verify all computers were tested
		proccessed_computers = []
		Dir.glob(pattern).each { |l| proccessed_computers.push l.split('_')[2] }
		unproccessed_computers = @computers_selected - proccessed_computers
		if unproccessed_computers.count != 0
			wrap "!!! WARNING !!!".red
			message = "The following [#{unproccessed_computers.count}] computers never began execution of the remote command and may need to be manually checked for issues."
			append_log("\n#{Time.now} | #{message}")
			wrap(message.yellow)
			append_log(print_computers(unproccessed_computers))
			puts print_computers(unproccessed_computers)
		end

		if @success
			wrap "!!! SUCCESS !!!".green
			wrap "Command [#{@command_selected.last.to_s.green}] was successfully completed on all #{remaining_computers} of the computers that received the command and no errors were encountered."
		else
			wrap "!!! FAILURE !!!".red
			wrap "Command [#{@command_selected.last.to_s.red}] failed on one or more of the #{remaining_computers} computers that received the remote command."
			wrap "Please check the output log after exiting the application for more detailed information."
		end

		puts append_log("\nTotal time for command execution on all computers: #{seconds_to_string(Time.now - command_start)}.").cyan

		# Insert command call to ping machines
		spinner_start
		wait_for_restarts if @command_selected.last.to_s.downcase.include?('prep for regression')
		wait_for_restarts if @command_selected.last.to_s.downcase.include?('testing')
		spinner_stop

		unless @output.empty?
			@output.sort!
			@output.delete_if{|o| o.empty?}
			puts append_log("\n==================================================\n")
			if @arguments_passed
				@output.each {|o| puts o}
			else
				puts "Would you like to see the output of the command?".yellow
				wrap "A summary is included at the bottom of the log file but you can view it here in the console as well."
				puts "Enter ".blue + 'Y'.green + " to view output, anything else to continue.".blue
				@output.each {|o| puts o} if STDIN.gets.chomp.downcase == 'y'
			end
		end

		if @arguments_passed
			puts append_log "\nWould you like to start a pry debugging session? ".yellow + "Y".green + "/" + "N\n".red
			selection = STDIN.gets.chomp.downcase
			append_log "User selected: [#{selection}]."
			binding.pry if selection == 'y'
			break
		else
			puts append_log("\n==================================================\n")
			wrap "Would you like to run another command? Enter 'y' to start over, anything else to exit the application.".yellow
			break unless STDIN.gets.chomp.downcase == 'y'
			log_counter +=1
		end
	end


	# delete all the remote log files that aren't from today
	puts "Clearing resources".blue
	spinner_start
	all_logs = Dir.glob("#{@remote_log_folder}/#{current_user}/*.txt")
	all_logs.delete_if{|f| !File.basename(f).include?(Time.now.strftime("%Y%m"))}
	all_logs.each{|f| File.delete(f)} if all_logs.count < 200
	spinner_stop
	wrap "Please check the output log for more detailed information about completed operations.".yellow
	puts append_log("\nTotal time spent in program: #{seconds_to_string(Time.now - app_start)}.").cyan
	exit_application

rescue Interrupt => e
	exit_application('interrupt', e)
rescue => e
	puts "ERROR ENCOUNTERED".red
	exit_application('error', e)
end