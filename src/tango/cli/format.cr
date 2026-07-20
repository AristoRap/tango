module Tango
  module CLI
    class FormatCommand
      private record Candidate, path : String, source : String, formatted : String

      def self.run(argv : Array(String), input : IO, output : IO, error : IO) : Int32
        new(argv, input, output, error).run
      end

      def initialize(argv : Array(String), @input : IO, @output : IO, @error : IO)
        @argv = argv.dup
      end

      def run : Int32
        parsed = parse
        return 1 unless parsed
        check, paths = parsed

        if paths == ["-"]
          return format_stdin(check)
        elsif paths.includes?("-")
          return usage("'-' must be the only formatting path")
        end

        paths = ["."] if paths.empty?
        files, discovery_failed = discover(paths)
        candidates, formatting_failed = format_files(files)
        failed = discovery_failed || formatting_failed

        if check
          candidates.each do |candidate|
            next if candidate.formatted == candidate.source

            @error.puts "tango: #{candidate.path} is not formatted (run `tango fmt #{candidate.path}`)"
            failed = true
          end
          return failed ? 1 : 0
        end

        return 1 if failed

        candidates.each do |candidate|
          next if candidate.formatted == candidate.source

          begin
            File.write(candidate.path, candidate.formatted)
            @output.puts "formatted #{candidate.path}"
          rescue ex : File::Error
            @error.puts "tango: couldn't write '#{candidate.path}': #{ex.message}"
            failed = true
          end
        end

        failed ? 1 : 0
      end

      private def parse : {Bool, Array(String)}?
        check = false
        paths = [] of String
        positional = false

        until @argv.empty?
          arg = @argv.shift
          if positional
            paths << arg
            next
          end

          case arg
          when "--check"
            check = true
          when "--"
            positional = true
          when "-"
            paths << arg
          else
            if arg.starts_with?('-')
              usage("unknown option: #{arg}")
              return nil
            end
            paths << arg
          end
        end

        {check, paths}
      end

      private def format_stdin(check : Bool) : Int32
        source = @input.gets_to_end
        result = Frontend::Crystal::Formatting.format(source, "stdin.tn")
        unless result.ok?
          render_diagnostics(source, "stdin.tn", result.diagnostics)
          return 1
        end

        formatted = result.formatted_source
        return 1 unless formatted
        if check
          if formatted != source
            @error.puts "tango: stdin.tn is not formatted"
            return 1
          end
        else
          @output.print formatted
        end
        0
      end

      private def discover(paths : Array(String)) : {Array(String), Bool}
        discovered = [] of String
        failed = false

        paths.each do |path|
          if File.file?(path)
            discovered << path
          elsif Dir.exists?(path)
            discovered.concat(Dir.glob(File.join(path, "**", "*.tn")))
          else
            @error.puts "tango: file or directory does not exist: #{path}"
            failed = true
          end
        end

        seen = Set(String).new
        files = discovered.sort!.select do |path|
          identity = canonical_identity(path)
          seen.add?(identity)
        end
        {files, failed}
      end

      private def format_files(files : Array(String)) : {Array(Candidate), Bool}
        candidates = [] of Candidate
        failed = false

        files.each do |path|
          source = begin
            File.read(path)
          rescue ex : File::Error
            @error.puts "tango: couldn't read '#{path}': #{ex.message}"
            failed = true
            next
          end

          result = Frontend::Crystal::Formatting.format(source, path)
          unless result.ok?
            render_diagnostics(source, path, result.diagnostics)
            failed = true
            next
          end

          formatted = result.formatted_source
          unless formatted
            @error.puts "tango: formatter returned no source for '#{path}'"
            failed = true
            next
          end

          candidates << Candidate.new(path, source, formatted)
        end

        {candidates, failed}
      end

      private def canonical_identity(path : String) : String
        File.realpath(path)
      rescue
        File.expand_path(path)
      end

      private def render_diagnostics(source : String, path : String, diagnostics : Array(Diagnostic)) : Nil
        index = Source::LineIndex.new(source)
        color = @error.tty? && ENV["NO_COLOR"]?.nil?
        diagnostics.each do |diagnostic|
          if diagnostic.file == path
            @error.puts Diagnostics::Renderer.render(source, diagnostic, path: path, color: color, index: index)
          else
            @error.puts diagnostic
          end
        end
      end

      private def usage(message : String) : Int32
        @error.puts "tango: #{message}"
        @error.puts "usage: tango fmt [--check] [path ...]"
        1
      end
    end
  end
end
