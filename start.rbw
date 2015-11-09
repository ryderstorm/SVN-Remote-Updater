require 'pry'
require 'colorize'

# exit if execution is part of build process
if Object.const_defined?(:Ocra)
	puts "Exiting start.rb during OCRA build process"
	exit
end
begin
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

	root = File.expand_path(File.dirname(__FILE__))
	file = root + '/wrapper.exe"'
	conemu = root + '/ConEmuPortable/ConEmu64.exe'
	command = "#{conemu} /cmd #{file}"
	command << ' network' unless ENV["OCRA_EXECUTABLE"].downcase.include?('c:')
	command << " #{ARGV[0]}" unless ARGV[0].nil?
	system(command)

rescue => e
	putsreport_error(e, 'Error encountered during start.rb')
end