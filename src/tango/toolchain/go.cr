module Tango
  module Toolchain
    module Go
      MIN_VERSION = {1, 21}

      enum Source
        Explicit
        Path
      end

      record Resolution, path : String, source : Source, formatter_path : String

      # Check failures are data owned by the toolchain boundary. Consumers
      # decide how to render them; program stderr is deliberately separate.
      record Result, status : Int32, diagnostics : Array(Diagnostic) = [] of Diagnostic do
        def success? : Bool
          status == 0 && diagnostics.empty?
        end
      end

      record FormattedSource, source : String?, diagnostics : Array(Diagnostic) = [] of Diagnostic do
        def success? : Bool
          !source.nil? && diagnostics.empty?
        end
      end

      private enum Action
        Run
        Build
      end

      private record Execution,
        action : Action,
        output_path : String? = nil,
        race : Bool = false do
        def args(main_path : String) : Array(String)
          case action
          in Action::Run
            args = ["run"]
            args << "-race" if race
            args << main_path
          in Action::Build
            destination = output_path || raise "build execution requires an output path"
            args = ["build"]
            args << "-race" if race
            args.concat(["-o", destination, main_path])
          end

          args
        end
      end

      private record PreparedExecution,
        toolchain : Resolution,
        args : Array(String),
        env : Hash(String, String)

      record BrokenPin, path : String do
        def message : String
          "TANGO_GO is set to #{path}, but no file exists there"
        end
      end

      record NotFound do
        def message : String
          "no Go toolchain found (run `tango doctor`)"
        end
      end

      record FormatterNotFound do
        def message : String
          "no gofmt found (run `tango doctor`)"
        end
      end

      def self.choose(explicit_request : String?, explicit_ok : Bool, on_path : String?, formatter_on_path : String? = nil) : Resolution | BrokenPin | NotFound | FormatterNotFound
        if explicit_request
          return BrokenPin.new(explicit_request) unless explicit_ok

          formatter_path = sibling_formatter(explicit_request) || formatter_on_path
          return formatter_path ? Resolution.new(explicit_request, Source::Explicit, formatter_path) : FormatterNotFound.new
        end

        if on_path
          formatter_path = formatter_on_path || Process.find_executable("gofmt")
          return formatter_path ? Resolution.new(on_path, Source::Path, formatter_path) : FormatterNotFound.new
        end

        NotFound.new
      end

      def self.resolve : Resolution | BrokenPin | NotFound | FormatterNotFound
        explicit = ENV["TANGO_GO"]?
        explicit_ok = explicit ? File.exists?(explicit) : false
        choose(explicit, explicit_ok, Process.find_executable("go"), Process.find_executable("gofmt"))
      end

      def self.parse_version(output : String) : {Int32, Int32}?
        if match = output.match(/go(\d+)\.(\d+)/)
          {match[1].to_i, match[2].to_i}
        end
      end

      def self.version(go_path : String) : {Int32, Int32}?
        output = IO::Memory.new
        status = Process.run(go_path, ["version"], output: output, error: Process::Redirect::Close, env: env)
        return nil unless status.success?

        parse_version(output.to_s)
      rescue
        nil
      end

      def self.meets_min?(version : {Int32, Int32}) : Bool
        version[0] > MIN_VERSION[0] || (version[0] == MIN_VERSION[0] && version[1] >= MIN_VERSION[1])
      end

      def self.format_source(source : String) : FormattedSource
        case toolchain = checked_toolchain
        in Resolution
          format_source(toolchain.formatter_path, source)
        in Diagnostic
          FormattedSource.new(nil, [toolchain])
        end
      end

      def self.run_source(source : String, source_path : String, output : IO, runtime_error : IO, race : Bool = false) : Result
        execute_source(source, source_path, Execution.new(Action::Run, race: race), output, runtime_error)
      end

      def self.build_source(source : String, source_path : String, output_path : String, build_error : IO, race : Bool = false) : Result
        execute_source(source, source_path, Execution.new(Action::Build, output_path, race), Process::Redirect::Close, build_error)
      end

      private def self.execute_source(source : String, source_path : String, execution : Execution, output : Process::Stdio, error : Process::Stdio) : Result
        case prepared = prepare_execution(source, source_path, execution)
        in PreparedExecution
          begin
            status = Process.run(prepared.toolchain.path, prepared.args, output: output, error: error, env: prepared.env)
            Result.new(status.exit_code)
          rescue ex : File::Error
            Result.new(1, [check(Diagnostics::CHECK_GO, "couldn't execute Go toolchain: #{ex.message}")])
          end
        in Array(Diagnostic)
          Result.new(1, prepared)
        end
      end

      private def self.prepare_execution(source : String, source_path : String, execution : Execution) : PreparedExecution | Array(Diagnostic)
        case toolchain = checked_toolchain
        in Diagnostic
          return [toolchain]
        in Resolution
          main_path = write_main(source, source_path, toolchain.formatter_path)
          return main_path.diagnostics unless main_path.success?
          path = main_path.source
          return main_path.diagnostics unless path

          diagnostics = vet(toolchain.path, path)
          return diagnostics unless diagnostics.empty?

          PreparedExecution.new(toolchain, execution.args(path), env(execution.race))
        end
      end

      private def self.checked_toolchain : Resolution | Diagnostic
        case result = resolve
        in Resolution
          begin
            prepare_cache
          rescue ex : File::Error
            return check(Diagnostics::CHECK_WORKSPACE, "couldn't prepare generated workspace: #{ex.message}")
          end

          if go_version = version(result.path)
            unless meets_min?(go_version)
              return check(Diagnostics::CHECK_GO_VERSION, "Go #{go_version[0]}.#{go_version[1]} is too old; need Go #{MIN_VERSION[0]}.#{MIN_VERSION[1]} or newer")
            end
          end

          result
        in BrokenPin, NotFound, FormatterNotFound
          check(Diagnostics::CHECK_GO, result.message)
        end
      end

      private def self.write_main(source : String, source_path : String, formatter_path : String) : FormattedSource
        main_path = Workspace::Layout.execution_module_file(source_path)
        formatted = format_source(formatter_path, source)
        return formatted unless formatted.success?
        rendered = formatted.source
        return formatted unless rendered

        Dir.mkdir_p(File.dirname(main_path))
        File.write(main_path, rendered)
        FormattedSource.new(main_path)
      rescue ex : File::Error
        FormattedSource.new(nil, [check(Diagnostics::CHECK_WORKSPACE, "couldn't write generated Go source: #{ex.message}", file: main_path)])
      end

      private def self.format_source(formatter_path : String, source : String) : FormattedSource
        formatted = IO::Memory.new
        diagnostics = IO::Memory.new
        status = Process.run(formatter_path, [] of String, input: IO::Memory.new(source), output: formatted, error: diagnostics, env: env)
        return FormattedSource.new(formatted.to_s) if status.success?

        FormattedSource.new(nil, [check(Diagnostics::CHECK_GOFMT, "gofmt failed", detail: diagnostics.to_s)])
      rescue ex
        FormattedSource.new(nil, [check(Diagnostics::CHECK_GOFMT, "gofmt failed: #{ex.message}")])
      end

      private def self.vet(go_path : String, main_path : String) : Array(Diagnostic)
        output = IO::Memory.new
        diagnostics = IO::Memory.new
        status = Process.run(go_path, ["vet", main_path], output: output, error: diagnostics, env: env)
        return [] of Diagnostic if status.success?

        tool_diagnostics(Diagnostics::CHECK_GO_VET, "go vet failed", "#{output}#{diagnostics}", main_path)
      rescue ex
        [check(Diagnostics::CHECK_GO_VET, "go vet failed: #{ex.message}", file: main_path)]
      end

      private def self.tool_diagnostics(code : String, fallback : String, output : String, file : String) : Array(Diagnostic)
        rendered = [] of Diagnostic

        output.each_line do |line|
          next if line.blank? || line.starts_with?('#')

          if match = line.match(/^(.*?):(\d+):(\d+):\s*(.*)$/)
            rendered << check(code, match[4], file: match[1], line: match[2].to_i, column: match[3].to_i)
          elsif match = line.match(/^(.*?):(\d+):\s*(.*)$/)
            rendered << check(code, match[3], file: match[1], line: match[2].to_i)
          end
        end

        return rendered unless rendered.empty?

        message = output.lines.first?.try(&.strip)
        [check(code, message.presence || fallback, file: file)]
      end

      private def self.check(code : String, message : String, file : String? = nil, line : Int32 = 1, column : Int32 = 1, detail : String? = nil) : Diagnostic
        Diagnostic.new(Diagnostic::Origin::Check, Diagnostic::Severity::Error, code, message, file: file, line: line, column: column, detail: detail)
      end

      private def self.sibling_formatter(go_path : String) : String?
        formatter_path = File.join(File.dirname(go_path), "gofmt")
        File.exists?(formatter_path) ? formatter_path : nil
      end

      private def self.prepare_cache
        Dir.mkdir_p(Workspace::Layout.go_build_cache_dir)
        Dir.mkdir_p(Workspace::Layout.go_module_cache_dir)
        Dir.mkdir_p(Workspace::Layout.go_temp_dir)
      end

      private def self.env(race : Bool = false) : Hash(String, String)
        vars = {
          "GOCACHE"    => Workspace::Layout.go_build_cache_dir,
          "GOMODCACHE" => Workspace::Layout.go_module_cache_dir,
          "GOTMPDIR"   => Workspace::Layout.go_temp_dir,
        }
        # The race detector is a cgo runtime — it needs a C toolchain.
        vars["CGO_ENABLED"] = "1" if race
        vars
      end
    end
  end
end
