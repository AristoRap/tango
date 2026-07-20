module Tango
  module CLI
    module Doctor
      record Check, label : String, value : String, detail : String, diagnostic : Diagnostic? = nil do
        def ok? : Bool
          diagnostic.nil?
        end
      end

      record Report, checks : Array(Check) do
        def ok? : Bool
          checks.all?(&.ok?)
        end

        def diagnostics : Array(Diagnostic)
          checks.compact_map(&.diagnostic)
        end
      end

      def self.inspect : Report
        checks = [] of Check
        checks << crystal_compiler_check
        checks << crystal_path_check
        checks << prelude_check

        go_check, version_check = go_checks
        checks << go_check
        checks << version_check
        checks << cache_check
        Report.new(checks)
      end

      def self.render(report : Report, io : IO) : Nil
        io.puts "tango doctor — environment check"
        io.puts
        report.checks.each do |check|
          status = check.ok? ? "ok" : "error"
          io.puts "  #{status.ljust(5)} #{check.label.ljust(15)} #{check.value}"
          io.puts "        #{check.detail}" unless check.detail.empty?
        end
      end

      private def self.crystal_compiler_check : Check
        executable = Process.find_executable("crystal")
        unless executable
          return failed(
            "Crystal compiler",
            "not found",
            Diagnostics::CHECK_CRYSTAL,
            "install Crystal so `crystal` is on PATH"
          )
        end

        output = IO::Memory.new
        errors = IO::Memory.new
        status = Process.run(executable, ["--version"], output: output, error: errors)
        unless status.success?
          detail = errors.to_s.strip.presence || "`crystal --version` failed"
          return failed("Crystal compiler", executable, Diagnostics::CHECK_CRYSTAL, detail)
        end

        version = output.to_s.lines.first?.try(&.strip).to_s
        Check.new("Crystal compiler", executable, version)
      rescue ex
        failed("Crystal compiler", executable || "not found", Diagnostics::CHECK_CRYSTAL, ex.message.to_s, ex.to_s)
      end

      private def self.crystal_path_check : Check
        case result = Toolchain::Crystal.resolve
        in Toolchain::Crystal::Path
          via = result.source.explicit? ? "CRYSTAL_PATH" : "`crystal env CRYSTAL_PATH`"
          missing = result.base
            .split(Process::PATH_DELIMITER, remove_empty: true)
            .select { |entry| Path.new(entry).absolute? && !Dir.exists?(entry) }
          unless missing.empty?
            return failed(
              "Crystal sources",
              result.base,
              Diagnostics::CHECK_CRYSTAL_PATH,
              "missing absolute path entries: #{missing.join(", ")}"
            )
          end
          Check.new("Crystal sources", result.base, "resolved via #{via}")
        in String
          failed("Crystal sources", "not found", Diagnostics::CHECK_CRYSTAL_PATH, result)
        end
      end

      private def self.prelude_check : Check
        path = Workspace::Layout.prelude_file
        if File.file?(path)
          Check.new("Tango prelude", path, "available as require #{Workspace::Layout.prelude_require.inspect}")
        else
          failed("Tango prelude", path, Diagnostics::CHECK_PRELUDE, "prelude file is missing")
        end
      end

      private def self.go_checks : {Check, Check}
        case result = Toolchain::Go.resolve
        in Toolchain::Go::Resolution
          via = result.source.explicit? ? "TANGO_GO" : "PATH"
          toolchain = Check.new("Go toolchain", result.path, "resolved via #{via}; gofmt: #{result.formatter_path}")
          version = Toolchain::Go.version(result.path)
          unless version
            return {
              toolchain,
              failed("Go version", "unknown", Diagnostics::CHECK_GO_VERSION, "`go version` failed"),
            }
          end

          major, minor = version
          minimum = Toolchain::Go::MIN_VERSION
          value = "go#{major}.#{minor}"
          if Toolchain::Go.meets_min?(version)
            {toolchain, Check.new("Go version", value, "meets required Go >= #{minimum[0]}.#{minimum[1]}")}
          else
            {
              toolchain,
              failed("Go version", value, Diagnostics::CHECK_GO_VERSION, "Tango needs Go >= #{minimum[0]}.#{minimum[1]}"),
            }
          end
        in Toolchain::Go::BrokenPin, Toolchain::Go::NotFound, Toolchain::Go::FormatterNotFound
          {
            failed("Go toolchain", "not usable", Diagnostics::CHECK_GO, result.message),
            Check.new("Go version", "not checked", "resolve the Go toolchain first"),
          }
        end
      end

      private def self.cache_check : Check
        paths = [
          Workspace::Layout.go_build_cache_dir,
          Workspace::Layout.go_module_cache_dir,
          Workspace::Layout.go_temp_dir,
        ]
        detail = paths.map do |path|
          state = Dir.exists?(path) ? "present" : "created on demand"
          "#{path} (#{state})"
        end.join("; ")
        Check.new("Local caches", File.expand_path(Workspace::Layout.cache_dir), detail)
      end

      private def self.failed(label : String, value : String, code : String, message : String, detail : String? = nil) : Check
        diagnostic = Diagnostic.new(
          Diagnostic::Origin::Check,
          Diagnostic::Severity::Error,
          code,
          message,
          detail: detail
        )
        Check.new(label, value, message, diagnostic)
      end
    end
  end
end
