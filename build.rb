require 'pry'
require 'fileutils'
require 'colorize'
require 'awesome_print'
app_start = Time.now
arguments_passed = false
unless ARGV[0].nil?
	if ARGV[0] == 'test'
		arguments_passed = true
		puts "Building application and executing in testing mode...\n\n".yellow
	end
end

def report_error(error, note = ' ')
	error_message = "=======================================================\n".light_red
	error_message << note.to_s.light_blue unless note.nil?
	# error_message << "\nMethod: ".ljust(12).cyan + __method__.to_s
	error_message << "\nTime: ".ljust(12).cyan + Time.now.localtime.to_s.green
	error_message << "\nComputer: ".ljust(12).cyan + @computer.green unless @computer.nil?
	error_message << "\nClass: ".ljust(12).cyan + error.class.to_s.light_red
	error_message << "\nMessage: ".ljust(12).cyan + error.message.light_red
	error_message << "\nBacktrace: ".ljust(12).cyan + error.backtrace.first.light_red
	error.backtrace[1..-1].each { |i| error_message << "\n           #{i.light_red}" }
	@errors.push "#{error_message}" unless @errors.nil?
	error_message
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

begin
	parent_folder = File.absolute_path(__FILE__).split('/')[0..-3].join('/')
	files_to_delete = []
	files_to_delete.concat Dir.glob((parent_folder + '/**/SVN_Remote_Updater_build*.exe'))
	files_to_delete.concat Dir.glob((parent_folder + '/**/remote.exe'))
	files_to_delete.concat Dir.glob((parent_folder + '/**/wrapper.exe'))
	puts "Deleting old files:".yellow
	files_to_delete.each do |f|
		puts File.basename(f).red
		File.delete(f)
	end
	new_app_name = "SVN_Remote_Updater_build#{Time.now.strftime("%Y%m%d%H%M%S")}.exe"
	File.open('build_history.txt', 'a') { |f| f.write(Time.now.to_s + " | " + new_app_name + "\n") }
	# binding.pry

	puts "=============================="
	puts "Starting build of remote.exe".cyan
	puts `ocra remote.rb library.rb nircmd.exe CCleaner64.exe qwinsta.exe ccleaner.ini`
	puts "=============================="
	puts "Finished building remote.exe".green
	puts "=============================="
	puts "Starting build of wrapper.exe".cyan
	puts `ocra wrapper.rb library.rb remote.exe paexec.exe build_history.txt`
	puts "=============================="
	puts "Finished building wrapper.exe".green
	puts "=============================="
	puts "Starting build of #{new_app_name}".cyan
	puts `ocra start.rbw wrapper.exe ConEmuPortable/** --output #{new_app_name}`
	puts "=============================="
	puts "Finished building #{new_app_name}".green

	final_location = parent_folder + '/SVN_Remote_Updater.exe'
	FileUtils.copy new_app_name, final_location

	puts "\n==============================\nBuild complete!\n==============================\n"
	puts "Build completed in #{seconds_to_string(Time.now - app_start)}".yellow
	puts "Please see the above log for any errors.\n\nThe latest build is: #{new_app_name}."

	if arguments_passed
		password = File.read('secret.txt')
		command = "start #{final_location} #{password}"
		puts "Executing new build with following command:\n".yellow + command.blue
		system(command)
		exit
	end
	puts "\nWould you like to update the builds on the network? ".yellow + 'Y'.green + '/' + 'N'.red
	load('update_network_build.rb') if gets.chomp.downcase == 'y'
	puts "\nTo start the new app, just press Enter. To exit, type ".blue + 'exit'.red + " and press enter.".blue
	selection = gets.chomp.downcase
	case selection
	when 'exit'
		exit
	when ''
		command = "start #{new_app_name}"
		system(command)
	else
		exit
	end
	exit
rescue => e
	report_error(e)

end
