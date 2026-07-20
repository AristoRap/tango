module Tango
  module CLI
    def self.run(argv : Array(String), input : IO, output : IO, error : IO) : Int32
      Command.new(argv, input, output, error).run
    end

    class Command
      def initialize(argv : Array(String), @input : IO, @output : IO, @error : IO)
        @argv = argv.dup
      end

      def run : Int32
        case command = @argv.shift?
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
        when "frontend"
          SemanticTransport::Producer.run(@argv, @input, @output, @error)
        when "core"
          SemanticTransport::Consumer.run(@argv, @input, @output, @error)
        when "lsp"
          ::Tango::Lsp::Server.new(@input, @output, @error).run
          0
        when "help", nil
          help(@output)
          0
        else
          @error.puts "unknown command: #{command}"
          help(@error)
          1
        end
      end

      private def run_program : Int32
        source_path = nil
        race = false
        release = false

        until @argv.empty?
          arg = @argv.shift
          case arg
          when "--race"
            race = true
          when "--release"
            release = true
          else
            source_path = arg
          end
        end

        source = SourceInput.read(source_path, @input)
        go_source = compile(source, compilation_profile(release))
        return 1 unless go_source
        result = ::Tango::Toolchain::Go.run_source(go_source, source.filename, @output, @error, race: race)
        DiagnosticOutput.render(source, result.diagnostics, @error)
        result.status
      end

      private def build_program : Int32
        source_path = nil
        output_path = nil
        race = false
        release = false

        until @argv.empty?
          arg = @argv.shift
          case arg
          when "-o", "--output"
            next_value = @argv.shift?
            return missing_value(arg) unless next_value
            output_path = next_value
          when "--race"
            race = true
          when "--release"
            release = true
          else
            source_path = arg
          end
        end

        source = SourceInput.read(source_path, @input)
        go_source = compile(source, compilation_profile(release))
        return 1 unless go_source
        result = ::Tango::Toolchain::Go.build_source(go_source, source.filename, output_path || ::Tango::Workspace::Layout.build_output(source.filename), @error, race: race)
        DiagnosticOutput.render(source, result.diagnostics, @error)
        result.status
      end

      private def emit : Int32
        target = @argv.shift?
        unless target == "go"
          @error.puts "usage: tango emit go [--release] [file|-]"
          return 1
        end

        release = !!@argv.delete("--release")
        source = SourceInput.read(@argv.shift?, @input)
        go_source = compile(source, compilation_profile(release))
        return 1 unless go_source
        formatted = ::Tango::Toolchain::Go.format_source(go_source)
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

        trace = @argv.delete("--trace")
        release = !!@argv.delete("--release")
        if trace && !target.in?("nir", "lir")
          @error.puts "--trace is only supported for tango dump nir and tango dump lir"
          return 1
        end

        source = SourceInput.read(@argv.shift?, @input)
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

      private def compile(source : SourceInput::Entry, profile : Compiler::CompilationProfile) : String?
        snapshot = ::Tango.snapshot(source.code, filename: source.filename, stable_path: source.stable_path?, profile: profile)
        if go_source = snapshot.go_source
          DiagnosticOutput.render(snapshot, @error)
          return go_source
        end

        DiagnosticOutput.render(snapshot, @error)
        nil
      end

      private def missing_value(flag : String) : Int32
        @error.puts "missing value for #{flag}"
        1
      end

      private def compilation_profile(release : Bool) : Compiler::CompilationProfile
        release ? Compiler::CompilationProfile::Release : Compiler::CompilationProfile::Development
      end

      private def help(io : IO)
        io.puts "usage:"
        io.puts "  tango run [file|-] [--race] [--release]"
        io.puts "  tango build [file|-] [-o output] [--race] [--release]"
        io.puts "  tango emit go [--release] [file|-]"
        io.puts "  tango dump nir|facts|plans|lir [--trace] [--release] [file|-]"
        io.puts "  tango lsp"
        io.puts "  tango doctor [--go-path|--go-min]"
        io.puts "  tango clean"
        io.puts "  tango fmt [--check] [path ...]"
        io.puts "internal/bootstrap:"
        io.puts "  tango frontend [file|-] --emit-semantic bundle|-"
        io.puts "  tango core [--release] bundle|- --emit-go"
      end
    end
  end
end
