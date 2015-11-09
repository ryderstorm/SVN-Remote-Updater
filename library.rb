require 'open3'
require 'awesome_print'
require 'colorize'
require 'pry'
require 'sys/filesystem'
require 'fileutils'
require 'win32/api'
require 'win32ole'
require 'win32/security'
require 'net/ping'
include Win32

# exit if execution is part of build process
if Object.const_defined?(:Ocra)
	puts "Exiting remote.rb during OCRA build process".yellow
	exit
end

# initialize constants and setup log folder
@errors = []
@output = []

# computer groups
sps = 'QASPS01,QASPS02,QASPS03,QASPS04,QASPS05,QASPS06,QASPS07,QASPS08,QASPS09,QASPS10,QASPS11,QASPS12,QASPS13,QASPS14,QASPS15,QASPS16,QASPS17,QASPS18,QASPS19,QASPS20,QASPS21,QASPS22,QASPS23,QASPS24,QASPS25'
web = 'QAWEB01,QAWEB02,QAWEB03,QAWEB04,QAWEB05,QAWEB06,QAWEB07,QAWEB08,QAWEB09,QAWEB10,QAWEB11,QAWEB12,QAWEB13,QAWEB14,QAWEB15,QAWEB16,QAWEB17,QAWEB18,QAWEB19,QAWEB20'
iseries = 'QAISR01,QAISR02,QAISR03,QAISR04,QAISR05,QAISR06,QAISR07,QAISR08,QAISR09,QAISR10,QAISR11,QAISR12,QAISR13,QAISR14,QAISR15'
edi = 'QAISR16,QAISR17'
sox = 'QAISR18,QAISR19,QAISR20,QAISR21,QAISR22'
mrm = 'QAMRM01,QAMRM02,QAMRM03'
trucomp = 'QATRU01,QATRU02'
psf = 'QAPSF01,QAPSF02'
testing = 'QAWEB11,QAWEB12,QAWEB13,QAWEB14,QAWEB15'
all = "#{sps},#{web},#{iseries},#{edi},#{sox},#{mrm},#{trucomp},#{psf}"
if @arguments_passed
	@computer_groups = {SPS:sps, Web:web, iSeries:iseries, EDI:edi, SOX:sox, MRM:mrm, TruComp:trucomp, PSF:psf, All_regression_computers:all, Custom_list_from_file:'', Testing:testing}
else
	@computer_groups = {SPS:sps, Web:web, iSeries:iseries, EDI:edi, SOX:sox, MRM:mrm, TruComp:trucomp, PSF:psf, All_regression_computers:all, Custom_list_from_file:''}
end


# menu list
@command_list = []
@command_list.push 'Install latest version of SVN'
@command_list.push 'Verify SVN is installed'
@command_list.push 'Switch C:\AutoSource_Prod to trunk and update to latest revision'
@command_list.push 'Switch C:\AutoSource_Prod to a specific branch/tag and update to latest revision'
@command_list.push 'Delete and recreate C:\AutoSource_Prod then do a fresh checkout of trunk'
@command_list.push 'Verify computers have at least 1GB of free disk space'
@command_list.push 'Clean disk space'
@command_list.push 'Get version numbers for installed software'
@command_list.push 'Get list of users active on each computer'
@command_list.push ['Prep for regression:','-Clean disk space','-Update to trunk','-Restart machine']

# software versions
@software = {}
@software.store("Internet Explorer",'"C:\\\Program Files (x86)\\\Internet Explorer\\\iexplore.exe"')
@software.store("UFT",'"C:\\\Program Files (x86)\\\HP\\\Unified Functional Testing\\\bin\\\UFT.exe"')
@software.store("TortoiseSVN",'"C:\\\Program Files\\\TortoiseSVN\\\bin\\\TortoiseProc.exe"')
@software.store("SVN Binary",'"C:\\\Program Files\\\TortoiseSVN\\\bin\\\svn.exe"')

# locations
@working_folder = 'C:\AutoSource_Prod'
@remote_log_folder = # network folder for containing log files
@svn_install_log = 'C:\svn_install_log.txt'
@svn_uninstall_log = 'C:\svn_uninstall_log.txt'
@temp_folder = (File.expand_path(File.dirname(__FILE__)) + '/').gsub!('/', "\\")
@paexec_location = @temp_folder + 'paexec.exe'
@remote_location = @temp_folder + 'remote.exe'
@svn_installer = # location of TortoiseSVN msi installer
@url = # repository url
@auth_directory = File.absolute_path(ENV['APPDATA'] + ("\\Subversion\\auth\\svn.simple")) + '/*'

# commands
@dir = 'dir C:\AutoSource_Prod'
@dir_tortoise = 'dir "c:\Program Files\TortoiseSVN\bin\TortoiseProc.exe"'
@dir_svn = 'dir "C:\Program Files\TortoiseSVN\bin\svn.exe"'
@install_svn = "msiexec /i #{@svn_installer} /quiet /qn /log #{@svn_install_log} ADDLOCAL=ALL"
@uninstall_svn = "msiexec /x #{@svn_installer} /log #{@svn_uninstall_log} /quiet /qn"
@revert = "revert -R C:\\AutoSource_Prod"
@cleanup = "cleanup C:\\AutoSource_Prod"
@info = "info C:\\AutoSource_Prod"
@switch = "switch --ignore-ancestry " + @url
@checkout = "checkout " + @url
@update = "update C:\\AutoSource_Prod"
@upgrade = "upgrade C:\\AutoSource_Prod"
@diff = "diff C:\\AutoSource_Prod"
@branches = 'list ' + @url + '/Branches'
@tags = 'list ' + @url + '/Tags'
@kill_UFT = 'taskkill /F /IM UFT.exe'
@kill_excel = 'taskkill /F /IM excel.exe'
@kill_ie = 'taskkill /F /IM iexplore.exe'
@kill_svn = 'taskkill /F /IM svn.exe'
@ccleaner = 'CCleaner64.exe /AUTO'
@delete_authentication = 'rmdir /s /q "%APPDATA%\Subversion\auth"'

# functions
def test_process
	return false unless reinstall_svn
	return false unless verify_svn_install
	return false unless update_to_trunk
	return true
end

def verify_svn_install
	result = execute_command(@dir_tortoise)
	unless result.first && result.last.include?("TortoiseProc.exe")
		append_log(log_failure("Unable to verify existence of TortoiseSVN"))
		return false
	end
	append_log(log_success("Successfully verified existence of TortoiseSVN"))

	result = execute_command(@dir_svn)
	unless result.first && result.last.include?("svn.exe")
		append_log(log_failure("Unable to verify existence of svn.exe"))
		return false
	end
	append_log(log_success("Successfully verified existence of svn.exe"))
	return true
end

def reinstall_svn
	return false unless uninstall_svn && install_svn
	return true
end

def install_svn
	File.delete(@svn_install_log) if File.exist?(@svn_install_log)
	return false unless kill_processes('svn')
	result = execute_command(@install_svn)
	sleep 1
	log = File.read(@svn_install_log).force_encoding("utf-16le").encode("utf-8")
	append_log("\tInstall log:")
	append_log(log.split("\r\n").join("\n\t"))
	unless result.first && (log.include?("Installation completed successfully.") or log.include?("Configuration completed successfully."))
		append_log(log_failure("Unable to install new version of TortoiseSVN"))
		return false
	end
	append_log(log_success("Successfully installed new version of TortoiseSVN"))
	return true
end

def uninstall_svn
	File.delete(@svn_uninstall_log) if File.exist?(@svn_uninstall_log)
	return false unless kill_processes('svn')
	result = execute_command(@uninstall_svn)
	sleep 1
	log = File.read(@svn_uninstall_log).force_encoding("utf-16le").encode("utf-8")
	append_log("\tUninstall log:")
	append_log(log.split("\r\n").join("\n\t"))
	if log.include?('This action is only valid for products that are currently installed.')
		append_log(log_success("Uninstallation of TortoiseSVN not necessary because it has already been removed"))
		return true
	end
	unless log.include?("Removal completed successfully.")
		append_log(log_failure("Unable to uninstall current version of TortoiseSVN"))
		return false
	end

	append_log(log_success("Successfully uninstalled current version of TortoiseSVN"))
	return true
end

def check_disk_space
	gb_available = free_disk_space
	if gb_available >= 1
		message = "#{ENV["COMPUTERNAME"]} has #{gb_available}GB of free space."
		append_log(log_success(message))
		@output.push message
		return true
	else
		message = "#{ENV["COMPUTERNAME"]} has less than 1GB of free space!"
		append_log(log_failure(message))
		@output.push message
		return false
	end
end

def free_disk_space
	stat = Sys::Filesystem.stat("/")
	stat.bytes_free / 1024 / 1024 / 1024
end

def clean_disk
	starting_space = free_disk_space
	command = File.expand_path(File.dirname(__FILE__)) + '/CCleaner64.exe /AUTO'
	result = execute_command(command)
	if result.first
		cleaned_space = starting_space - free_disk_space
		append_log(log_success("Successfully cleaned up #{cleaned_space}GB of disk space"))
		return true
	else
		append_log(log_failure("Failed to clean up disk space"))
		retun false
	end
end

def prep_for_regression
	success = false
	log_ip_address
	if update_to_trunk
		if clean_disk
			if restart_local
				success = true
			end
		end
	end
	unless success
		append_log(log_failure("Prep for regression failed, see output log for details"))
		return false
	end
	append_log(log_success("Prep for regression was successful!"))
	return true
end

def verify_autosource_prod
	if Dir.exist?('C:\AutoSource_Prod')
		append_log(log_success("Verified existence of C:\AutoSource_Prod"))
		return true
	end
	append_log(log_failure("Directory C:\AutoSource_Prod does not exist"))
	return false
end

def delete_autosource_prod
	if Dir.exist?(@working_folder)
		begin
			FileUtils.remove_entry(@working_folder)
		rescue => e
			append_log(log_failure("Unable to remove directory C:\AutoSource_Prod"))
			append_log("\tError: #{e.message}")
			log_error(e.message)
			return false
		end
	else
		append_log(log_success("AutoSource_Prod doesn't need to be deleted because it doesn't exist"))
		return true
	end
	append_log(log_success("Successfully deleted C:\AutoSource_Prod"))
	return true
end

def perform_fresh_checkout
	return false unless kill_processes
	return false unless delete_autosource_prod
	append_log('Beginning fresh checkout')
	result = execute_command('svn ' + @credentials + @checkout + @branch + ' C:\AutoSource_Prod')
	unless result.first
		append_log(log_failure("Fresh checkout of branch/tag [#{@branch}] to C:\AutoSource_Prod was unsuccessful"))
		return false
	end
	append_log(log_success("Successfully checked out branch/tag [#{@branch}] to C:\AutoSource_Prod"))
	success = cleanup
	return false unless success
	success = verify_no_diff
	return false unless success
	return true
end

def verify_working_copy_url
	result = execute_command('svn ' + @credentials + @info)

	if result.to_s.include?("Please see the 'svn upgrade' command")
		result = execute_command('svn ' + @credentials + @upgrade)
	end

	unless result.first
		append_log(log_warning("Unable to verify that C:\AutoSource_Prod is a valid working copy"))
		return false
	end

	unless result.last.split("\n")[4].include?(@url)
		append_log(log_warning("C:\AutoSource_Prod is not associated with the correct repository"))
		return false
	end
	append_log(log_success("Verified C:\AutoSource_Prod is associated with the correct repository"))
	@working_copy_info = result.last.split("\n")
	return true
end

def switch
	# IMPORTANT: 'verify_working_copy_url' must be run PRIOR to this def being run
	if @working_copy_info.nil? || @working_copy_info.empty?
		append_log(log_failure("[verify_working_copy_url] has not been run yet! application cannot continue, please check [switch] in library.rb"))
		exit_application
	end

	if @working_copy_info[3].split("^").last == @branch
		append_log(log_success("Working copy already set to #{@branch}"))
		return true
	else
		result = execute_command('svn ' + @credentials + @switch + @branch + ' C:\AutoSource_Prod')
		unless result.first
			append_log(log_failure("Unable to switch working copy to #{@branch}"))
			return false
		end
		append_log(log_success("Successfully switched working copy to #{@branch}"))
		return true
	end
end

def cleanup
	result = execute_command('svn ' + @credentials + @revert)
	unless result.first
		append_log(log_failure("Unable to revert working copy"))
		return false
	end
	result = execute_command('svn ' + @credentials + @cleanup)
	unless result.first
		append_log(log_failure("Unable to cleanup working copy"))
		return false
	end
	append_log(log_success("Successfully cleaned up working copy"))
	return true
end

def update_working_copy
	result = execute_command('svn ' +@credentials + @update)
	unless result.first
		append_log(log_failure("Unable to update working copy"))
		return false
	end
	append_log(log_success("Successfully updated working copy"))
	return true
end

def verify_no_diff
	result = execute_command('svn ' + @credentials + @diff)
	unless result.first && result.last.empty?
		append_log(log_failure("Update working copy was unsuccessful; differences still remain"))
		return false
	end
	append_log(log_success("Verified working copy contains no differences from repository"))
	return true
end

def kill_processes(process = 'all')

	# close all instances of UFT, Excel, SVN, and IE to prevent them from locking any files
	current_processes = `tasklist`.downcase
	if (process == 'all' or process == 'uft')
		if current_processes.include?('uft.exe')
			result = execute_command(@kill_UFT)
			unless result.first
				append_log(log_failure("Unable to close all instances of UFT"))
				return false
			end
			append_log(log_success("Successfully closed all instances of UFT"))
		else
			append_log("\tNo open instances of UFT detected\n")
		end
	end

	if (process == 'all' or process == 'excel')
		if current_processes.include?('excel.exe')
			result = execute_command(@kill_excel)
			unless result.first
				append_log(log_failure("Unable to close all instances of Excel"))
				return false
			end
			append_log(log_success("Successfully closed all instances of Excel"))
		else
			append_log("\tNo open instances of Excel detected\n")
		end
	end

	if (process == 'all' or process == 'ie')
		if current_processes.include?('iexplore.exe')
			result = execute_command(@kill_ie)
			unless result.first
				append_log(log_failure("Unable to close all instances of Internet Explorer"))
				return false
			end
			append_log(log_success("Successfully closed all instances of Internet Explorer"))
		else
			append_log("\tNo open instances of Internet Explorer detected\n")
		end
	end

	if (process == 'all' or process == 'svn')
		if current_processes.include?('svn.exe')
			result = execute_command(@kill_svn)
			unless result.first
				append_log(log_failure("Unable to close all instances of svn.exe"))
				return false
			end
			append_log(log_success("Successfully closed all instances of svn.exe"))
		else
			append_log("\tNo open instances of svn.exe detected\n")
		end
	end

	return true
end

def update_to_trunk
	@branch = '/Trunk/AutoSource_Prod'
	update_to_tag
end

def update_to_tag

	# close programs that could cause issues
	return false unless kill_processes

	# verify AutoSource_Prod exists
	result = verify_autosource_prod
	return perform_fresh_checkout unless result

	# verify AutoSource_Prod is a working folder of the correct repository
	result = verify_working_copy_url
	return perform_fresh_checkout unless result

	# switch the working folder to the given branch if it is not already
	result = switch
	return perform_fresh_checkout unless result

	# clean up the working folder
	result = cleanup
	return perform_fresh_checkout unless result

	# update the working folder
	result = update_working_copy
	return perform_fresh_checkout unless result

	# verify there are no differences
	result = verify_no_diff
	return perform_fresh_checkout unless result

	return true
end

def select_branch_or_tag
	@branch_different = true
	5.times do
		append_log("#{Time.now} | Prompting user to select branch/tag")
		wrap "Retrieving tags and branches from SVN server...".light_magenta
		clearscreen
		wrap "<<<<< TAG OR BRANCH SELECTION >>>>>".yellow
		branches = execute_command('svn ' +@credentials + @branches)
		unless (branches.first)
			append_log(log_failure("Unable to get branches from SVN "))
			wrap "There was an issue getting the list of banches from the server. Please see the output log for details.".red
			wrap "Press enter to exit the application."
			STDIN.gets.chomp
			exit_application
		end

		tags = execute_command('svn ' + @credentials + @tags)
		unless (tags.first)
			append_log(log_failure("Unable to get tags from SVN "))
			wrap "There was an issue getting the list of tags from the server. Please see the output log for details.".red
			wrap "Press enter to exit the application."
			STDIN.gets.chomp
			exit_application
		end

		tags_and_branches = []
		tags.last.split("\n").each{ |t| tags_and_branches.push "Tag|#{t.gsub('/', '')}"}
		branches.last.split("\n").each { |b| tags_and_branches.push "Branch|#{b.gsub('/', '')}" }
		wrap "The following tags/branches are available:"
		tags_and_branches.each_with_index do |branch_tag, i|
			type, name = branch_tag.split("|")
			puts "#{i + 1}. ".yellow + "#{type.center(10, '-')}".blue + " #{name}".cyan
		end
		wrap "Which tag or branch do you want to update to?"
		wrap "Type the number corresponding to the one you want, " + "1-#{tags_and_branches.size}".yellow + ", and press enter."
		branch_selection = STDIN.gets.chomp
		exit_application('user') if branch_selection.downcase == 'exit'

		unless (1..tags_and_branches.count).include?(branch_selection.to_i)
			wrap "You entered [#{branch_selection.yellow}]. This is not a valid selection. Press enter to try again.".red
		 	STDIN.gets.chomp
			clearscreen
			next
		end

		type, branch_name = tags_and_branches[branch_selection.to_i-1].split('|')
		type == 'Tag' ? branch_name.prepend("/Tags/") :	branch_name.prepend("/Branches/")

		wrap "The following branch/tag has been selected:"
		puts (@url + branch_name).yellow
		wrap "Is this correct? Enter " + 'Y'.green + " to confirm, " + 'exit'.red + " to exit the application, or anything else to select again."
		selection = STDIN.gets.chomp
		exit_application('user') if selection.downcase == 'exit'
		if selection.downcase == 'y' then
			append_log("\n\n#{Time.now} | User selected branch or tag [#{branch_name}]")
			clearscreen
			@branch = branch_name
			return
		end
		clearscreen
	end
	clearscreen
	puts append_log("#{Time.now} | Branch/tag selection failed after 5 attempts - exiting application.")
	exit_application
end

def select_computer_group
	append_log("#{Time.now} | Prompting user to select computer group")
	5.times do
		clearscreen
		wrap "<<<<< COMPUTER SELECTION >>>>>".yellow
		@computer_groups.keys.each_with_index do |k, i|
			puts "#{i + 1}.".yellow + " #{k.to_s.gsub("_", ' ')}".cyan
		end
		wrap "Which group of computers do you want to work with?"
		wrap "Type the number corresponding to the group you want, " + "1-#{@computer_groups.size}".yellow + ", and press enter."
		wrap "To exit the program, type " + 'exit'.red + " and press enter."
		group_selection = STDIN.gets.chomp
		exit_application('user') if group_selection.downcase == 'exit'
		unless (1..@computer_groups.count).include?(group_selection.to_i)
			clearscreen
			wrap "You entered [#{group_selection}]. This is not a valid selection. Press enter to try again.".red
		 	STDIN.gets.chomp
			clearscreen
			next
		end

		if @computer_groups.keys[group_selection.to_i - 1].to_s.downcase == 'custom_list_from_file'
			list_location = ENV['HOME'] + '/Desktop/SVN_Remote_Updater_Computer_List.txt'
			File.delete(list_location) if File.exist?(list_location)
			File.write(list_location, @computer_groups[:All_regression_computers].split(',').join("\n"))
			clearscreen
			wrap "You selected to read a list of computers from a file. The following file has been created on your desktop:"
			puts list_location.gsub('/', "\\").yellow
			wrap "It includes a list of all the regression computers. Press Enter to open the file, then remove any computers you don't want to work with and save the file."
			wrap "IMPORTANT: please do not add any non-regression computers to this list. All computer names should begin with 'QA'.".cyan
			wrap "Press Enter to open the file..."
		 	STDIN.gets.chomp
			system("start #{list_location}")
			clearscreen
			wrap "Please make sure you have saved your edits in the file before continuing.".cyan
			wrap "If you intend to use this combination of computers on a regular basis, make a copy of the file after you have finished editing it and save it under a different name so you can reuse the list in the future."
			wrap "Once you have have finished editing the file and saved it, press Enter to continue..."
		 	STDIN.gets.chomp
			@computer_groups[@computer_groups.keys[group_selection.to_i - 1]] = read_file(list_location).join(',')
		end

		clearscreen
		computers = @computer_groups.values[group_selection.to_i - 1].split(',')
		wrap "The following #{computers.count.to_s.cyan} computers have been selected:"
		puts print_computers(computers)
		wrap "Is this correct? Enter " + 'Y'.green + " to confirm, " + 'exit'.red + " to exit the application, or anything else to select again."
		selection = STDIN.gets.chomp
		exit_application('user') if selection.downcase == 'exit'
		if selection.downcase == 'y'
			append_log("\n\n#{Time.now} | User selected computer group [#{@computer_groups.keys[group_selection.to_i - 1].to_s}]:\n\t[#{@computer_groups.values[group_selection.to_i - 1]}]")
			# return computers.join(',')
			return computers
			clearscreen
		end
		clearscreen
	end
	clearscreen
	puts append_log("#{Time.now} | Computer selection failed after 5 attempts - exiting application.").red
	exit_application
end

def verify_command(command_selection)
	append_log("#{Time.now} | Verifying command with user")
	5.times do
		clearscreen
		puts "<<<<< COMMAND VERIFICATION >>>>>".yellow
		puts "\nYou have selected to run this command:"
		puts "*** #{command_selection.cyan} ***"
		if @branch_different
			puts "\nWith branch:"
			puts "#{@url + @branch}".cyan
		end
		puts "\nOn the following computers:"
		puts print_computers(@computers_selected)
		puts "\nAs user [#{@username.cyan}] with password [#{@password.cyan}]."
		puts "\n===============================================\n"
		wrap "If this is not correct, type ".yellow + 'exit'.red + " and press enter to exit the program, or type ".yellow + 'restart'.blue + " and press enter to start over and change your selection.".yellow
		puts "\n==============================================="
		wrap "If this is correct, please type ".green + 'continue'.cyan + " and press enter to execute the command.".green
		selection = STDIN.gets.chomp
		case selection
		when 'exit'
			exit_application('user')
		when 'restart'
			return selection
		when 'continue'
			return selection
		when ''
			puts "Your selection: [#{selection.yellow}], is not a valid selection, please try again...".red
			STDIN.gets.chomp
			next
		else
			puts "Your selection: [#{selection.yellow}], is not a valid selection, please try again...".red
			STDIN.gets.chomp
			next
		end
	end
	clearscreen
	puts append_log("#{Time.now} | Command verification failed after 5 attempts - exiting application.").red
	exit_application
end

def show_warning_and_get_password
	append_log("#{Time.now} | Warning user and prompting for password")
	5.times do
		clearscreen
		puts "\n<<<<< !!!WARNING!!! >>>>>\n\n".red
		wrap "Executing commands on remote computers may close all instances of the following programs on those computers:"
		['TortoiseSVN', 'Internet Explorer', 'Excel','UFT'].each { |i| puts "#{i}".yellow }
		wrap 'Any unsaved data in these applications will be irrevocably lost and any testing currently in progress will be interrupted.'
		wrap 'By using this program to execute commands on the remote computers, you accept full responsibility for any potential data loss caused by closing these programs.'.red
		puts "\n==============================================="
		wrap "If you would like to continue, please type the password for user:"
		puts @username.yellow
		wrap "And press enter. Type " + 'exit'.red + " and press enter to exit this application."
		wrap "Don't worry - the password you enter here is never stored in a file or saved in any way.".green
		selection = STDIN.gets.chomp
		exit_application('user') if selection == 'exit'
		if selection == ''
			puts 'Password cannot be blank, please press'.red + 'enter'.cyan + '  to try again...'.red
		 	STDIN.gets.chomp
			next
		end
		puts "\n==============================================="
		puts "You entered:\n\n"
		puts selection.yellow
		puts "\nIs this correct? Enter " + 'Y'.green + " to confirm, anything else to try again."
		next unless STDIN.gets.chomp.downcase == 'y'
		if verify_password(selection)
			@password = selection
			@credentials = "--username #{@username} --password #{selection} "
			return
		else
			puts "The provided password, ".yellow + selection.red + ", could not be used to login to QAWEB01.\nPlease press ".yellow + "enter".cyan + " to try again, or type ".yellow + 'exit'.red + ' to exit the application.'.yellow
			selection = STDIN.gets.chomp
			exit_application('user') if selection.downcase == 'exit'
		end
	end
	clearscreen
	puts append_log("#{Time.now} | Password entry failed after 5 attempts - exiting application.").red
	exit_application
end

def verify_password(password)
	spinner_start
	command = "#{@paexec_location} \\\\QAWEB01 -d -u corp.cdw.com\\#{@username} -p #{password} systeminfo"
	results = execute_command(command)
	spinner_stop
	if results.first
		message = "Successfully verified that username #{@username.green} and password #{password.green} can be used to login to regresssion machines!"
		wrap(message)
		append_log(log_success(message))
		puts "Please press ".yellow + "enter".blue + " to continue...".yellow
		STDIN.gets.chomp
		success = true
	else
		log_error(results[2])
		append_log(log_failure("Unable to verify that username #{@username.red} and password #{password.red} can be used to login to regresssion machines."))
		success = false
	end
	return success
end

def print_computers(computers)
	case computers.count
	when 1
		return computers.first.yellow
	when 0
		return false
	end
	result = ""
	indexed = Array.new
	(1..computers.size).each { |i| indexed.push i.to_s.rjust(computers.length.to_s.length, '0').yellow + '. ' + computers[i-1].ljust(computers.max_by(&:length).length).cyan}.to_a
	cols = indexed.each_slice((indexed.size+2)/4).to_a
	cols.first.zip( *cols[1..-1] ).each{|row| result.concat (row.map{|c| c.ljust(computers.length.to_s.length) if c}.join("    ")) + "\n" }
	return result
end

def select_command
	append_log("#{Time.now} | Prompting user to select command")
	5.times do
		clearscreen
		wrap "<<<<< COMMAND SELECTION >>>>>".yellow
		@command_list.each_with_index do |c, i|
			if c.is_a?Array
				wrap("#{i + 1}.".yellow + c[0].cyan)
				c[1..-1].each{|d| puts "\t#{d}".cyan}
			else
				wrap "#{i + 1}.".yellow + c.cyan
			end
		end
		puts "\n==============================================="
		wrap "Which command would you like to run?"
		wrap "Type the number corresponding to the command you want, " + "1-#{@command_list.size}".yellow + ", and press enter."
		wrap "To exit the program, type " + 'exit'.red + " and press enter."
		selection = STDIN.gets.chomp
		exit_application('user') if selection.downcase == 'exit'
		unless (1..@command_list.count).include?(selection.to_i)
			clearscreen
			wrap "You entered [#{selection}]. This is not a valid selection. Press enter to try again.".red
		 	STDIN.gets.chomp
			clearscreen
			next
		end
		clearscreen
		command_number = selection.to_i
		command = @command_list[command_number - 1]
		puts "\nYou selected command:\n\n*** #{command.to_s.cyan} ***"
		wrap "Is this correct? Enter " + 'Y'.green + " to continue, " + 'exit'.red + " to exit the application, or anything else to select again."
		selection = STDIN.gets.chomp
		exit_application('user') if selection.downcase == 'exit'
		if selection.downcase == 'y'
			append_log("\n\n#{Time.now} | User selected command [#{command_number}: #{command}]")
			return [command_number, command]
			clearscreen
		end
		clearscreen
	end
	clearscreen
	puts append_log("#{Time.now} | Command selection failed after 5 attempts - exiting application.").red
	exit_application
end

def check_software_versions
	success = true
	@software.each do |k,v|
		command = 'wmic datafile where name=' + v + ' get version'
		results = execute_command(command)
		if results.first
			version = results.last.delete("Version").strip
			@output.push "#{@current_computer}|#{k}|#{version}"
			append_log(log_success("Successfully verified version for [#{k}]\n\tVersion number is: [#{version}]"))
		else
			log_error(results[2])
			append_log(log_failure("Unable to verify version for [#{k}]"))
			success = false
		end
	end
	return success
end

def log_error(error)
	@errors.push @current_computer + " encountered the following error:" + strip_text(error)
end

def strip_text(text)
	temp = []
	text.to_s.split("\n").each{ |t| temp.push t unless t.strip.empty?}
	temp.join("\n\t\t")
end

def execute_command(command)
	message = "\n\n#{Time.now} | Running the following command on [#{@current_computer}]:\n\t#{command}"
	output, error, status = Open3.capture3(command)
	message <<"\n\tStatus: #{status.to_s.empty? ? "there was no status message returned by the command!" : status.to_s.strip}"
	message << "\tError: #{strip_text(error)}" unless error.to_s.empty?
	message << "\tOutput: #{strip_text(output)}" unless output.to_s.empty?
	if status.to_s.downcase.include?("exit 0")
		message << "\tCommand completed successfully!"
		append_log(message)
		return [true, status, error, output]
	else
		message << "\tCommand execution failed!"
		append_log(message)
		return [false, status, error, output]
	end
end

def clearscreen
	puts "\e[H\e[2J"
	puts '==========================================================================='.blue
end

def exit_application(exception = false, error = '')
	# kill paexec.exe if it exists
	system('taskkill /im paexec.exe /f /t') if `tasklist`.include?('paexec.exe')
	spinner_stop
	case exception
	when 'interrupt'
		# clearscreen
		wrap '<<<<< APPLICATION INTERRUPTED!!! >>>>>'.yellow
		wrap "The application has been interrupted unexpectedly..."
		append_log("\n#{Time.now} | Application encountered an interrupt")
		@reset_auth = true
	when 'error'
		# clearscreen
		wrap '<<<<< APPLICATION ERROR!!! >>>>>'.red
		wrap "The application has encountered an error and terminated unexpectedly...".yellow
		wrap "Please report this error to Damien Storm:".yellow
		wrap("damien.storm@orasi.com".blue + " | ".yellow + "damisto@cdw.com".blue)
		puts "**************************************************".yellow
		puts "**************************************************".yellow
		append_log("\n#{Time.now} | Application encountered the following error:\n#{report_error(error)}")
		puts "**************************************************".yellow
		puts "**************************************************".yellow
		@reset_auth = true
		puts "Press ".yellow + 'enter'.red + ' to continue exiting the application...'.yellow
		STDIN.gets.chomp
	when 'user'
		wrap '<<<<< EXITING APPLICATION >>>>>'.cyan
		wrap "You chose to exit the application...".yellow
		append_log("\n#{Time.now} | User chose to exit the application via typing 'exit'.")
	when 'network'
		wrap "You are attempting to run this program from somewhere other than your local computer(for example, the K: drive or some other network drive). Please copy it to your local computer, somewhere on the C: drive, before trying to run the applicaiton again.".red
		wrap "Press ".yellow + "enter".blue + " to exit the application".yellow
		STDIN.gets.chomp
		Kernel.exit!
	end

	puts "\n\n===============================================".yellow
	puts "Starting application cleanup...".yellow
	spinner_start

	# revert SVN authentication folder
	if @reset_auth
		auth_files = Dir.glob(@auth_directory)
		unless auth_files.empty?
			auth_files.each do |f|
				current_path = File.absolute_path(f)
				if current_path.include?('_backup')
					new_path = current_path.sub('_backup', '')
					FileUtils.mv(current_path, new_path)
				else
					FileUtils.rm(current_path)
				end
			end
		end
	end
	spinner_stop
	append_log("\n\n#{Time.now} | SVN_Remote_Updater closed normally.")
	puts "\n\n===============================================".yellow
	wrap "Program output has been logged to a file in the same folder as this application:"
	puts File.expand_path(@logfile).gsub('/', '\\').blue
	if @arguments_passed
		system("start #{@logfile}")
		puts "\nExiting testing mode execution".light_magenta
		Kernel.exit!
	else
		wrap("Press Enter to open the logfile or type ".green + 'exit'.red + " to exit the application and close this window.".green)
		if STDIN.gets.chomp.downcase == 'exit'
			puts 'Exiting application...'.light_magenta
			Kernel.exit!
		end
		puts "Opening log file...".blue
		system("start #{@logfile}")
	end
	puts "\nPress Enter to exit the application.".green
	response = STDIN.gets.chomp
	binding.pry if response.downcase == 'pry'
	puts "Exiting application...".light_magenta
	Kernel.exit!
end

def append_log(text)
	return if @logfile.nil?
	if (!@password.nil? && text.include?(@password))
		text.gsub!(" #{@password} ", ' ***PASSWORD_REDACTED*** ')
	end
	f = File.open(@logfile, 'a')
	results = f.write "#{text}\n".uncolorize
	f.close
	text
end

def read_file(file)
	return "File is too large to read" if File.size(file) > 5000000
	results = Array.new
	f = File.open(file, 'r')
	f.each { |l| results << l.chomp }
	f.close
	results
end

def seconds_to_string(s)
	# d = days, h = hours, m = minutes, s = seconds
	m = (s / 60).floor
	s = (s % 60).floor
	h = (m / 60).floor
	m = m % 60
	d = (h / 24).floor
	h = h % 24

	output = "#{s} second#{pluralize(s)}" if (s > 0)
	output = "#{m} minute#{pluralize(m)}, #{s} second#{pluralize(s)}" if (m > 0)
	output = "#{h} hour#{pluralize(h)}, #{m} minute#{pluralize(m)}, #{s} second#{pluralize(s)}" if (h > 0)
	output = "#{d} day#{pluralize(d)}, #{h} hour#{pluralize(h)}, #{m} minute#{pluralize(m)}, #{s} second#{pluralize(s)}" if (d > 0)

	return output
end

def pluralize(number)
	return "s" unless number == 1
	return ""
end

def wrap(s, width=65)
	lines = []
	line = ""
	s.split(/\s+/).each do |word|
		if line.size + word.size >= width - 2
			lines << line
			line = word
		elsif line.empty?
			line = word
		else
			line << " " << word
		end
	end
	lines << line if line
	puts "\n" + lines.join("\n") + "\n"
end

def position_console
	hWnd = API.new('FindWindow', 'PP', 'L', 'user32').call(nil, ENV["OCRA_EXECUTABLE"].dup)
	return if hWnd == 0
	move_window = API.new('MoveWindow', 'LIIIII', 'I', 'user32')
	move_window.call(hWnd, 0, 0, 750, 750, true)
end

def restart_local
	command = 'shutdown -t 0 -r'
	append_log(log_warning("Restarting system via [#{command}]"))
	# append_log("=====|||||=====")
	result = execute_command(command)
	unless result.first
		append_log(log_failure("Restart command failed"))
		return false
	end
	append_log(log_success("Restart command succeeded!"))
	return true
end

def check_active_users
	result, status, error, output = execute_command("#{@temp_folder}qwinsta.exe")
	if result
		user = ''
		output.split("\n").each do |i|
			if i.downcase.include?('active')
				user = i.split[1]
				break
			end
		end
		message = @current_computer + (user.empty? ? " | No users are actively logged in." : " | User [#{user}] is active on this machine")
		@output.push message
	end
	return result
end

def log_ip_address
	ip_address = 'not found'
	ips = Socket.ip_address_list
	ips.each{|ip| ip_address = ip.ip_address if ip.ip_address[0..2] == '10.'}
	append_log("RECORDED_IP_ADDRESS:#{@current_computer}|#{ip_address}")
	return ip_address == 'not found' ? false : true
end

def wait_for_restarts
	puts append_log("\nWaiting up to 2 minutes for computers to complete restart process...\n").yellow
	sleep 5 # give computers time to initiate restart
	success = true
	# get all the computer/ip combinations
	all_computers = {}
	File.readlines(@logfile).each do |l|
		if l.include?("RECORDED_IP_ADDRESS")
			pc, ip = l.split("RECORDED_IP_ADDRESS:").last.strip.split('|')
			next if all_computers.keys.include?(pc.to_sym)
			all_computers.store(pc, ip) unless ip == 'not found'
		end
	end

	if all_computers.empty?
		message = "No recorded ip addresses were found in the log!\nYou may have to check the machines manually to verify they restarted successfully.\nPlease see the log for details.".yellow
		wrap message
		append_log(log_warning(message))
		return false
	end
	# start pinging all the computers
	start_time = Time.now
	restarted = {}
	loop do
		if (Time.now - start_time) > 120
			spinner_stop
			message = "Waiting for all computers to reboot has taken longer than 2 minutes and will now exit.".red
			puts message
			append_log(log_warning(message))
			success = false
			break
		end
		break if all_computers.empty?
		threads = []
		all_computers.each do |pc, ip|
# 	if the computer responds to a ping
			threads.push Thread.new{
				if Net::Ping::WMI.new(ip).ping?
					append_log("#{Time.now} | Computer [#{pc}] is now responding to pings on IP [#{ip}].")
					restarted.store(pc, ip)
					all_computers.delete(pc)
				end
			}
			sleep 0.25
		end
		threads.each{|t| t.join(5)}
		sleep 0.25
	end
# report results
	spinner_stop
	puts "\n"
	if success
		message = "All #{restarted.count.to_s.green} computers have finished the restart process!".green
		puts message
		append_log(log_success(message + "\n#{print_computers(restarted.collect{|k,v| "#{k} | #{v}"})}"))
		return true
	else
		message = "There was a problem restarting the following #{all_computers.count} computers. They may need to be manually checked for issues.\n".yellow + print_computers(all_computers.keys)
		puts message
		append_log(log_failure(message))
		return false
	end
end

def log_success(message)
	wrapper = "+".ljust(message.length+11, '+')
	"\n" + wrapper + "\n+++++ " + message + "\n" + wrapper + "\n"
end

def log_failure(message)
	wrapper = "-".ljust(message.length+11, '-')
	"\n" + wrapper + "\n----- " + message + "\n" + wrapper + "\n"
end

def log_warning(message)
	wrapper = "!".ljust(message.length+11, '!')
	"\n" + wrapper + "\n!!!!! " + message + "\n" + wrapper + "\n"
end

def report_error(error, note = ' ')
	error_message = "=======================================================\n".red
	error_message << note.to_s.blue unless note.nil?
	# error_message << "\nMethod: ".ljust(12).cyan + __method__.to_s
	error_message << "\nTime: ".ljust(12).cyan + Time.now.localtime.to_s.green
	error_message << "\nComputer: ".ljust(12).cyan + @computer.green unless @computer.nil?
	error_message << "\nClass: ".ljust(12).cyan + error.class.to_s.red
	error_message << "\nMessage: ".ljust(12).cyan + error.message.red
	error_message << "\nBacktrace: ".ljust(12).cyan + error.backtrace.first.red
	error.backtrace[1..-1].each { |i| error_message << "\n           #{i.red}" }
	@errors.push "#{error_message}" unless @errors.nil?
	puts error_message
	return error_message.uncolorize
end

def spinner
	loop do
		['|', '/', '-', '\\'].each do |c|
			print "\r#{c}  "
			sleep 0.1
		end
	end
end

def spinner_start
	puts "\n"
	@spinner = Thread.new{spinner}
end

def spinner_stop
	unless @spinner.nil?
		@spinner.kill
		@spinner = nil
	end
	puts "\n"
end

def get_percent_complete(completed, total)
	return "Cannot get percentage when total is zero! total:[#{total}]" if total == 0
	percentage = completed.to_f / total.to_f * 100.to_f
	"#{percentage.round(1).to_s.rjust(5)}% completed".rjust(5)
end

# =============================================================================
# =============================================================================
# Testing Area=================================================================
# =============================================================================
# =============================================================================

def testing
	# return log_ip_address
	# return check_active_users
	# return prep_for_regression

	# use nircmd to create shortcuts for the following commands that need to be run manually?
	# http://qaqcprod2vh/qcbin/start_a.jsp?common=true
	# 'javaws http://10.19.4.41:8080/computer/' + @current_computer + '/slave-agent.jnlp'

	# unless result
	# 	append_log(log_failure("Jenkins slave setup failed"))
	# 	return false
	# end
	# append_log(log_success("Successfully setup machine as a Jenkins slave!"))

	time = rand(5)
	append_log(log_warning("Waiting for #{time} seconds..."))
	sleep time
	return true
end

def update_ota
	# system('C:\Windows\System32\perfmon.exe')
	# system('C:\Windows\System32\taskmgr.exe')
	# kill_processes
	# command = '\\\mir\qa\Orasi\Damien\temp\ALMUninstaller.exe /cleanup'
	# result = execute_command(command)
	# unless result.first
	# 	append_log(log_failure("ALMUninstaller failed!"))
	# 	return false
	# end
	files = ['C:\Users\All Users\HP\ALM-Client\qaqcprod2vh\OTAClient.dll', 'C:\ProgramData\HP\ALM-Client\qaqcprod2vh\OTAClient.dll', 'C:\Users\All Users\HP\ALM-Client\qaqcprod2vh\WebClient.dll', 'C:\ProgramData\HP\ALM-Client\qaqcprod2vh\WebClient.dll', 'C:\Users\damisto\AppData\Local\HP\ALM-Client\qaqcprod2vh\OTAClient.dll', 'C:\Users\damisto\AppData\Local\HP\ALM-Client\qaqcprod2vh\WebClient.dll']
	# success = true
	# folders = ['C:\ProgramData\HP\ALM-Client', 'C:\Users\qatester1\AppData\Local\HP\ALM-Client']
	# folders = ['C:\ProgramData\HP', 'C:\Users\qatester1\AppData\Local\HP']
	# folders.each{ |f| Dir.exist?(f) ? (append_log("\tDeleting folder [#{f}]");FileUtils.remove_entry(f)) : append_log("\tFolder [#{f}] already gone!")}
	# folders.each{ |f| success = false if Dir.exist?(f)}
	files.each{|f| append_log("#{File.exist?(f) ? 'PRESENT' : 'NOT PRESENT'} | #{f}")}
	# unless success
	# 	append_log(log_failure("OTA folders still present on machine"))
	# 	return false
	# end
	# append_log(log_success("OTA folders successfully removed!"))
	# command = 'MSIEXEC /a "\\\mir\qa\Orasi\Damien\temp\HP_ALM_Client_qaqcprod2vh_v1.msi" /passive'
	# result = execute_command(command)
	# files.each{|f| append_log("#{File.exist?(f) ? 'PRESENT' : 'NOT PRESENT'} | #{f}")}
	# unless result.first
	# 	append_log(log_failure("HP_ALM_Client install failed"))
	# 	return false
	# end
	# append_log(log_failure("HP_ALM_Client install was successful!"))


	return true
end


def install_java
	return true if verify_java_install

	result = execute_command('\\\mir\qa\Orasi\Damien\temp\jre-8u51-windows-i586.exe /s')
	unless result.first
		append_log(log_failure("Java install failed"))
		return false
	end
	append_log(log_success("Successfully installed java!"))
	return true
end

def verify_java_install
	unless Dir.exist?('C:\Program Files (x86)\Java')
		append_log(log_failure('Java folder [C:\Program Files (x86)\Java] does not exist, so Java is not installed!'))
		return false
	end
	result = execute_command('java -version')
	unless result.first
		append_log(log_warning("Java is not installed"))
		return false
	end
	append_log(log_success("Java is already installed!"))
	return true
end

def add_java_site_exception
	file = 'C:\Users\qatester1\AppData\LocalLow\Sun\Java\Deployment\security\exception.sites'
	line = 'http://10.19.4.41:8080/'
	if File.exist?(file)
		if File.read(file).include?(line)
			append_log(log_success("Jenkins server already added to java exception list!"))
			return true
		end
	end
	File.open(file, "a"){ |f| f.puts line}
	unless File.read(file).include?(line)
		append_log(log_failure("Failed to add Jenkins server to java site exception list"))
		return false
	end
	append_log(log_success("Successfully added Jenkins server to java exception list!"))
	return true
end

