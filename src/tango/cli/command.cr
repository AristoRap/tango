module Tango
  module CLI
    def self.run(argv : Array(String), input : IO, output : IO, error : IO) : Int32
      Command.new(argv, input, output, error).run
    end

    class Command
      private enum Audience
        Product
        Developer
      end

      private record CommandDefinition,
        name : String,
        description : String,
        audience : Audience

      COMMANDS = [
        CommandDefinition.new("run", "Compile and run a Tango program", Audience::Product),
        CommandDefinition.new("build", "Compile a Tango executable", Audience::Product),
        CommandDefinition.new("fmt", "Format Tango source files", Audience::Product),
        CommandDefinition.new("doctor", "Check the compiler environment", Audience::Product),
        CommandDefinition.new("clean", "Remove Tango build artifacts", Audience::Product),
        CommandDefinition.new("emit", "Print generated target source", Audience::Developer),
        CommandDefinition.new("dump", "Inspect compiler phases", Audience::Developer),
        CommandDefinition.new("lsp", "Run the editor language server", Audience::Developer),
      ]

      def initialize(argv : Array(String), @input : IO, @output : IO, @error : IO)
        @argv = argv.dup
      end

      def run : Int32
        command, help_requested, version_requested, invalid = parse_entrypoint

        if invalid
          @error.puts "tango: #{invalid}"
          @error.puts "Run `tango --help` for usage."
          return 1
        end

        if version_requested
          unless @argv.empty?
            @error.puts "tango: --version does not accept arguments"
            return 1
          end
          @output.puts "tango #{::Tango::VERSION}"
          return 0
        end

        if help_requested || command.nil?
          return render_requested_help
        end

        case command
        when "run"
          run_program
        when "build"
          build_program
        when "emit"
          emit
        when "dump"
          dump
        when "doctor"
          doctor
        when "clean"
          clean
        when "fmt"
          FormatCommand.run(@argv, @input, @output, @error)
        when "lsp"
          ::Tango::Lsp::Server.new(@input, @output, @error).run
          0
        else
          @error.puts "unknown command: #{command}"
          @error.puts "Run `tango --help` for usage."
          1
        end
      rescue ex : File::Error
        @error.puts "tango: file operation failed: #{ex.message}"
        1
      end

      private record ProgramOptions,
        source_path : String?,
        output_path : String?,
        race : Bool,
        release : Bool

      private record SourceArgument,
        valid : Bool,
        path : String?

      private record CompiledProgram,
        source : String,
        modules : Array(::Tango::Target::Go::Runtime::ModuleRequirement)

      private def parse_entrypoint : {String?, Bool, Bool, String?}
        command = nil
        help_requested = false
        version_requested = false
        invalid = nil
        arguments = @argv.dup
        parser = OptionParser.new

        COMMANDS.each do |definition|
          name = definition.name
          parser.on(name, definition.description) do
            command = name
            parser.stop
          end
        end
        parser.on("help", "Show help") do
          help_requested = true
          parser.stop
        end
        parser.on("version", "Show the Tango version") do
          version_requested = true
          parser.stop
        end
        parser.on("-h", "--help", "Show help") { help_requested = true }
        parser.on("-V", "--version", "Show the Tango version") { version_requested = true }
        parser.invalid_option { |option| invalid = "unknown option: #{option}" }

        parser.parse(arguments)
        @argv = arguments
        if command.nil? && !help_requested && !version_requested && !@argv.empty?
          invalid = "unknown command: #{@argv.first}"
        end
        {command, help_requested, version_requested, invalid}
      end

      private def render_requested_help : Int32
        include_developer = @argv == ["--all"]
        unless @argv.empty? || include_developer
          @error.puts "tango: usage: tango help [--all]"
          return 1
        end

        @output.puts help_parser(include_developer)
        0
      end

      private def help_parser(include_developer : Bool) : OptionParser
        parser = OptionParser.new
        parser.banner = "Tango #{::Tango::VERSION}\n\nUsage: tango <command> [options]\n\nCommands:"
        parser.summary_indent = "  "
        parser.summary_width = 12

        COMMANDS.each do |definition|
          next unless definition.audience.product?

          parser.on(definition.name, definition.description) { }
        end

        if include_developer
          parser.separator
          parser.separator "Developer and editor commands:"
          COMMANDS.each do |definition|
            next unless definition.audience.developer?

            parser.on(definition.name, definition.description) { }
          end
        end

        parser.separator
        parser.separator "Options:"
        parser.on("-h", "--help", "Show this help") { }
        parser.on("-V", "--version", "Show the Tango version") { }
        unless include_developer
          parser.separator
          parser.separator "Run `tango help --all` to show developer and editor commands."
        end
        parser
      end

      private def run_program : Int32
        options = parse_program_options(build: false)
        return 1 unless options

        source = SourceInput.read(options.source_path, @input)
        compiled = compile(source, compilation_profile(options.release))
        return 1 unless compiled
        result = ::Tango::Toolchain::Go.run_source(compiled.source, source.filename, @output, @error, race: options.race, modules: compiled.modules)
        DiagnosticOutput.render(source, result.diagnostics, @error)
        result.status
      end

      private def build_program : Int32
        options = parse_program_options(build: true)
        return 1 unless options

        source = SourceInput.read(options.source_path, @input)
        compiled = compile(source, compilation_profile(options.release))
        return 1 unless compiled
        result = ::Tango::Toolchain::Go.build_source(compiled.source, source.filename, options.output_path || ::Tango::Workspace::Layout.build_output(source.filename), @error, race: options.race, modules: compiled.modules)
        DiagnosticOutput.render(source, result.diagnostics, @error)
        result.status
      end

      private def emit : Int32
        target = @argv.shift?
        unless target == "go"
          @error.puts "usage: tango emit go [--release] [file|-]"
          return 1
        end

        if @argv.count("--release") > 1
          command_usage("usage: tango emit go [--release] [file|-]", "--release specified more than once")
          return 1
        end
        release = !!@argv.delete("--release")
        source_argument = single_source_argument("usage: tango emit go [--release] [file|-]")
        return 1 unless source_argument.valid
        source = SourceInput.read(source_argument.path, @input)
        compiled = compile(source, compilation_profile(release))
        return 1 unless compiled
        formatted = ::Tango::Toolchain::Go.format_source(compiled.source)
        unless formatted.success?
          DiagnosticOutput.render(source, formatted.diagnostics, @error)
          return 1
        end
        rendered = formatted.source
        return 1 unless rendered

        @output.print rendered
        0
      end

      private def dump : Int32
        target = @argv.shift?
        unless target.in?("nir", "facts", "plans", "lir")
          @error.puts "usage: tango dump nir|facts|plans|lir [--trace] [--release] [file|-]"
          return 1
        end

        usage = "usage: tango dump nir|facts|plans|lir [--trace] [--release] [file|-]"
        if @argv.count("--trace") > 1 || @argv.count("--release") > 1
          command_usage(usage, "dump flags may be specified only once")
          return 1
        end
        trace = @argv.delete("--trace")
        release = !!@argv.delete("--release")
        if trace && !target.in?("nir", "lir")
          @error.puts "--trace is only supported for tango dump nir and tango dump lir"
          return 1
        end

        source_argument = single_source_argument(usage)
        return 1 unless source_argument.valid
        source = SourceInput.read(source_argument.path, @input)
        snapshot = ::Tango.snapshot(source.code, filename: source.filename, stable_path: source.stable_path?, profile: compilation_profile(release))

        rendered =
          if trace
            case target
            when "nir" then ::Tango::Dump::LowerTrace.render_nir(snapshot)
            when "lir" then ::Tango::Dump::LowerTrace.render_lir(snapshot)
            else            ""
            end
          else
            case target
            when "nir"   then ::Tango::Dump::NIR.render(snapshot)
            when "facts" then ::Tango::Dump::Facts.render(snapshot)
            when "plans" then ::Tango::Dump::Plans.render(snapshot)
            when "lir"   then ::Tango::Dump::LIR.render(snapshot)
            else              ""
            end
          end

        @output.print rendered
        DiagnosticOutput.render(snapshot, @error)

        snapshot.ok? ? 0 : 1
      end

      private def doctor : Int32
        case probe = @argv.shift?
        when nil
          report = Doctor.inspect
          Doctor.render(report, @output)
          report.ok? ? 0 : 1
        when "--go-path"
          return doctor_usage unless @argv.empty?

          case result = ::Tango::Toolchain::Go.resolve
          in ::Tango::Toolchain::Go::Resolution
            @output.puts result.path
            0
          in ::Tango::Toolchain::Go::BrokenPin, ::Tango::Toolchain::Go::NotFound, ::Tango::Toolchain::Go::FormatterNotFound
            @error.puts Diagnostic.new(Diagnostic::Origin::Check, Diagnostic::Severity::Error, Diagnostics::CHECK_GO, result.message)
            1
          end
        when "--go-min"
          return doctor_usage unless @argv.empty?

          version = ::Tango::Toolchain::Go::MIN_VERSION
          @output.puts "#{version[0]}.#{version[1]}"
          0
        else
          doctor_usage
        end
      end

      private def doctor_usage : Int32
        @error.puts "usage: tango doctor [--go-path|--go-min]"
        1
      end

      private def clean : Int32
        unless @argv.empty?
          @error.puts "usage: tango clean"
          return 1
        end

        result = Clean.run
        if diagnostic = result.diagnostic
          @error.puts diagnostic
          return 1
        end

        if result.removed
          @output.puts "removed #{result.path}"
        else
          @output.puts "already clean: #{result.path}"
        end
        0
      end

      private def compile(source : SourceInput::Entry, profile : Compiler::CompilationProfile) : CompiledProgram?
        snapshot = ::Tango.snapshot(source.code, filename: source.filename, stable_path: source.stable_path?, profile: profile)
        if go_source = snapshot.go_source
          DiagnosticOutput.render(snapshot, @error)
          return CompiledProgram.new(go_source, snapshot.go_modules)
        end

        DiagnosticOutput.render(snapshot, @error)
        nil
      end

      private def parse_program_options(build : Bool) : ProgramOptions?
        source_path : String? = nil
        output_path : String? = nil
        race = false
        release = false
        usage = build ? "usage: tango build [file|-] [-o output] [--race] [--release]" : "usage: tango run [file|-] [--race] [--release]"

        until @argv.empty?
          arg = @argv.shift
          case arg
          when "-o", "--output"
            return command_usage(usage, "#{arg} is only supported by tango build") unless build
            next_value = @argv.shift?
            unless next_value
              command_usage(usage, "missing value for #{arg}")
              return nil
            end
            return command_usage(usage, "missing value for #{arg}") if next_value.starts_with?('-')
            return command_usage(usage, "output path specified more than once") if output_path
            output_path = next_value
          when "--race"
            return command_usage(usage, "--race specified more than once") if race
            race = true
          when "--release"
            return command_usage(usage, "--release specified more than once") if release
            release = true
          else
            return command_usage(usage, "unknown option: #{arg}") if arg.starts_with?('-') && arg != "-"
            return command_usage(usage, "multiple source files are not supported") if source_path
            source_path = arg
          end
        end

        ProgramOptions.new(source_path, output_path, race, release)
      end

      private def single_source_argument(usage : String) : SourceArgument
        if unknown = @argv.find { |arg| arg.starts_with?('-') && arg != "-" }
          command_usage(usage, "unknown option: #{unknown}")
          return SourceArgument.new(false, nil)
        end
        if @argv.size > 1
          command_usage(usage, "multiple source files are not supported")
          return SourceArgument.new(false, nil)
        end
        SourceArgument.new(true, @argv.shift?)
      end

      private def command_usage(usage : String, message : String) : Nil
        @error.puts "tango: #{message}"
        @error.puts usage
      end

      private def compilation_profile(release : Bool) : Compiler::CompilationProfile
        release ? Compiler::CompilationProfile::Release : Compiler::CompilationProfile::Development
      end
    end
  end
end
