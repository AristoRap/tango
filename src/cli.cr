require "./tango/cli"

exit Tango::CLI.run(ARGV, STDIN, STDOUT, STDERR)
