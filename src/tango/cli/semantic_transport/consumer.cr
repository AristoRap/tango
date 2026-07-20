module Tango
  module CLI
    module SemanticTransport
      # Host-neutral compiler half of the bootstrap boundary. Decoding restores
      # the ordinary frontend result consumed by the one compiler core.
      class Consumer
        USAGE = "usage: tango core [--release] bundle|- --emit-go"

        def self.run(argv : Array(String), input : IO, output : IO, error : IO) : Int32
          new(argv, input, output, error).run
        end

        def initialize(argv : Array(String), @input : IO, @output : IO, @error : IO)
          @argv = argv.dup
        end

        def run : Int32
          bundle_path, profile = arguments
          return 1 unless bundle_path

          document = Frontend::Bundle::Codec.load(read_bundle(bundle_path))
          snapshot = Compiler::CoreDriver.run(document.to_frontend_result, profile)
          DiagnosticOutput.render(snapshot, @error)
          return 1 unless snapshot.ok?

          go_source = snapshot.go_source
          return fail_with("semantic bundle did not contain a normalized program") unless go_source

          formatted = Toolchain::Go.format_source(go_source)
          DiagnosticOutput.render(snapshot.source, formatted.diagnostics, @error)
          rendered = formatted.source
          return 1 unless rendered && formatted.diagnostics.empty?

          @output.print rendered
          0
        rescue exception : Frontend::Bundle::UnsupportedVersionError | Frontend::Bundle::CodecError | File::Error
          fail_with(exception.message || exception.class.name)
        end

        private def arguments : {String?, Compiler::CompilationProfile}
          bundle_path = nil
          emit_go = false
          release = false

          until @argv.empty?
            case argument = @argv.shift
            when "--emit-go"
              return usage if emit_go
              emit_go = true
            when "--release"
              return usage if release
              release = true
            else
              return usage if argument.starts_with?("-") && argument != "-"
              return usage if bundle_path
              bundle_path = argument
            end
          end

          return usage unless bundle_path && emit_go
          profile = release ? Compiler::CompilationProfile::Release : Compiler::CompilationProfile::Development
          {bundle_path, profile}
        end

        private def usage : {String?, Compiler::CompilationProfile}
          @error.puts USAGE
          {nil, Compiler::CompilationProfile::Development}
        end

        private def read_bundle(path : String) : String
          path == "-" ? @input.gets_to_end : File.read(path)
        end

        private def fail_with(message : String) : Int32
          @error.puts "tango core: #{message}"
          1
        end
      end
    end
  end
end
