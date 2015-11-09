require (File.expand_path(File.dirname(__FILE__))) + '/library.rb'
begin
	if Object.const_defined?(:Ocra)
		puts "Exiting remote.rb during OCRA build process".yellow
		exit
	end

	command_number = ARGV[0]
	log_info = ARGV[1]
	# branch_tag = ARGV[2]
	@credentials = "--username #{ARGV[2]} --password #{ARGV[3]} "
	@password = ARGV[3]
	@branch = ARGV[4]
	if command_number.nil?
		puts "No command specified!"
		exit
	end

	@current_computer = ENV["COMPUTERNAME"]
	@logfile = "#{@remote_log_folder}/#{log_info.split("_").last}/#{log_info}_#{@current_computer}_Output.txt"
	command_name = command_number.to_i == 100 ? "testing" : @command_list[command_number.to_i - 1]
	append_log("\n\n#{Time.now} | Beginning execution of command [#{command_number}: #{command_name}] on [#{@current_computer}]")

	# this case statement corresponds to the items in @command_list
	case command_number.to_i
	when 1
		success = reinstall_svn
	when 2
		success = verify_svn_install
	when 3
		success = update_to_trunk
	when 4
		success = update_to_tag
	when 5
		success = perform_fresh_checkout
	when 6
		success = check_disk_space
	when 7
		success = clean_disk
	when 8
		success = check_software_versions
	when 9
		success = check_active_users
	when 10
		success = prep_for_regression
	when 100
		success = testing
	else
		puts "Invalid command number was entered: [#{command_number}]"
		exit 1
	end

	if success and @errors.empty?
		message = "<<<<< #{@current_computer} | Success! All operations completed successfully. >>>>>"
		append_log(log_success(message))
		append_log("=====|||||=====")
		append_log("\n#{@output.sort.join("\n")}")
		exit 0
	else
		message = "<<<<< #{@current_computer} | Failure! Some operations failed. >>>>>"
		append_log(log_failure(message))
		@errors.each { |e| append_log(e)}
		append_log("=====|||||=====")
		append_log("\n#{@output.sort.join("\n")}")
		exit 1
	end

rescue Interrupt => e
	append_log("\n#{Time.now} | Application encountered an interrupt: \n\t#{e}\n")
	message = "<<<<< #{@current_computer} | Failure! Some operations failed. >>>>>"
	append_log(log_failure(message))
	append_log("=====|||||=====")
	exit
rescue => e
	append_log("\n#{Time.now} |\n" + report_error(e))
	message = "<<<<< #{@current_computer} | Failure! Some operations failed. >>>>>"
	append_log(log_failure(message))
	append_log("=====|||||=====")
	exit
end