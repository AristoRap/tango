# The spec executable doubles as a current-source CLI subprocess for the one
# process-boundary integration example. This avoids testing a stale `bin/tango`
# while still crossing real OS process and filesystem boundaries.
private def semantic_process_env(name : String) : String
  ENV[name]? || begin
    STDERR.puts "missing semantic transport spec process variable: #{name}"
    STDERR.flush
    LibC._exit(2)
  end
end

if role = ENV["TANGO_SPEC_SEMANTIC_PROCESS"]?
  argv = case role
         when "producer"
           [
             "frontend",
             semantic_process_env("TANGO_SPEC_SEMANTIC_SOURCE"),
             "--emit-semantic",
             semantic_process_env("TANGO_SPEC_SEMANTIC_BUNDLE"),
           ]
         when "consumer"
           ["core", "--release", semantic_process_env("TANGO_SPEC_SEMANTIC_BUNDLE"), "--emit-go"]
         when "ordinary"
           ["emit", "go", "--release", semantic_process_env("TANGO_SPEC_SEMANTIC_SOURCE")]
         else
           STDERR.puts "unknown semantic transport spec process role: #{role}"
           STDERR.flush
           LibC._exit(2)
         end

  status = Tango::CLI.run(argv, STDIN, STDOUT, STDERR)
  STDOUT.flush
  STDERR.flush
  LibC._exit(status)
end
