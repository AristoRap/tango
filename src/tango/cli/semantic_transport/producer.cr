module Tango
  module CLI
    module SemanticTransport
      # Crystal-hosted half of the bootstrap boundary. It performs the same
      # graph loading and semantic normalization as ordinary compilation, then
      # writes only Tango-owned bundle data.
      class Producer
        USAGE = "usage: tango frontend [file|-] --emit-semantic bundle|-"

        def self.run(argv : Array(String), input : IO, output : IO, error : IO) : Int32
          new(argv, input, output, error).run
        end

        def initialize(argv : Array(String), @input : IO, @output : IO, @error : IO)
          @argv = argv.dup
        end

        def run : Int32
          source_path, bundle_path = arguments
          return 1 unless bundle_path

          source = SourceInput.read(source_path, @input)
          frontend = Compiler::Driver.frontend(source.to_source, Frontend::SourceGraph::DISK_RESOLVER)
          document = Frontend::Bundle::Document.from(
            frontend,
            frontend_version: "tango/#{Tango::VERSION} crystal/#{Compiler::Driver.frontend_host_version}",
            prelude_version: "tango/#{Tango::VERSION}"
          )
          write_bundle(bundle_path, Frontend::Bundle::Codec.dump(document))
          0
        rescue exception : File::Error | ArgumentError
          fail_with(exception.message || exception.class.name)
        end

        private def arguments : {String?, String?}
          source_path = nil
          bundle_path = nil

          until @argv.empty?
            case argument = @argv.shift
            when "--emit-semantic"
              return usage if bundle_path
              bundle_path = @argv.shift?
              return usage unless bundle_path
            else
              return usage if argument.starts_with?("-") && argument != "-"
              return usage if source_path
              source_path = argument
            end
          end

          return usage unless bundle_path
          {source_path, bundle_path}
        end

        private def usage : {String?, String?}
          @error.puts USAGE
          {nil, nil}
        end

        private def write_bundle(path : String, contents : String) : Nil
          if path == "-"
            @output.print contents
            return
          end

          temporary = "#{path}.tmp-#{Process.pid}-#{Random.rand(1_000_000)}"
          begin
            File.write(temporary, contents)
            File.rename(temporary, path)
          ensure
            File.delete(temporary) if File.exists?(temporary)
          end
        end

        private def fail_with(message : String) : Int32
          @error.puts "tango frontend: #{message}"
          1
        end
      end
    end
  end
end
