# The spec executable doubles as a current-source CLI subprocess for the one
# process-boundary integration example. This avoids testing a stale `bin/tango`
# while still crossing real OS process and filesystem boundaries.
require "../../src/tango/cli/semantic_transport"

private def semantic_process_env(name : String) : String
  ENV[name]? || begin
    STDERR.puts "missing semantic transport spec process variable: #{name}"
    STDERR.flush
    LibC._exit(2)
  end
end

if role = ENV["TANGO_SPEC_SEMANTIC_PROCESS"]?
  status = case role
           when "producer"
             Tango::CLI::SemanticTransport::Producer.run([
               semantic_process_env("TANGO_SPEC_SEMANTIC_SOURCE"),
               "--emit-semantic",
               semantic_process_env("TANGO_SPEC_SEMANTIC_BUNDLE"),
             ], STDIN, STDOUT, STDERR)
           when "consumer"
             Tango::CLI::SemanticTransport::Consumer.run([
               "--release",
               semantic_process_env("TANGO_SPEC_SEMANTIC_BUNDLE"),
               "--emit-go",
             ], STDIN, STDOUT, STDERR)
           when "ordinary"
             Tango::CLI.run(["emit", "go", "--release", semantic_process_env("TANGO_SPEC_SEMANTIC_SOURCE")], STDIN, STDOUT, STDERR)
           else
             STDERR.puts "unknown semantic transport spec process role: #{role}"
             STDERR.flush
             LibC._exit(2)
           end
  STDOUT.flush
  STDERR.flush
  LibC._exit(status)
end
