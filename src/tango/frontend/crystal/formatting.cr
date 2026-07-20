require "compiler/crystal/formatter"

module Tango
  module Frontend
    module Crystal
      # The single Tango source-formatting boundary. Crystal owns every layout
      # decision; Tango only contains failures as shared diagnostics so CLI and
      # editor consumers observe the same result without spawning a subprocess.
      module Formatting
        record Result, formatted_source : String?, diagnostics : Array(Diagnostic) do
          def ok? : Bool
            @formatted_source != nil && @diagnostics.none? { |diagnostic| diagnostic.severity.error? }
          end
        end

        def self.format(source : String, filename : String = "source.tn") : Result
          Result.new(::Crystal.format(source, filename: filename), [] of Diagnostic)
        rescue ex : ::Crystal::CodeError
          file = Source::File.new(filename, source)
          Result.new(nil, [DiagnosticTranslator.from(ex, file)])
        rescue ex : InvalidByteSequenceError
          Result.new(nil, [failure("file '#{filename}' is not valid UTF-8: #{ex.message}")])
        rescue ex
          Result.new(nil, [failure("formatter failed for '#{filename}': #{ex.message}")])
        end

        private def self.failure(message : String) : Diagnostic
          Diagnostic.new(
            Diagnostic::Origin::Check,
            Diagnostic::Severity::Error,
            Diagnostics::CHECK_FORMATTER,
            message
          )
        end
      end
    end
  end
end
