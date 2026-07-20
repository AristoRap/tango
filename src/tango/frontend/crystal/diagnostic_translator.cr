module Tango
  module Frontend
    module Crystal
      # Converts host-frontend exceptions into Tango-owned diagnostics before
      # they cross the semantic handoff.
      module DiagnosticTranslator
        def self.from(ex : ::Crystal::CodeError, source : Source::File? = nil) : Diagnostic
          primary = primary_error(ex)
          from(ex, primary, source)
        end

        def self.from(ex : ::Crystal::CodeError, source : Source::CompilationUnit) : Diagnostic
          primary = primary_error(ex)
          filename = true_filename(primary)
          file = filename.try { |path| source.file?(path) }
          file ||= source.entrypoint unless filename
          from(ex, primary, file)
        end

        private def self.from(ex : ::Crystal::CodeError, primary : ::Crystal::CodeError, source : Source::File?) : Diagnostic
          line, column, reported_size =
            case primary
            when ::Crystal::SyntaxException, ::Crystal::TypeException
              {primary.line_number || 1, primary.column_number || 1, primary.size || 0}
            else
              {1, 1, 0}
            end

          # `primary_error` already selected the deepest source-located frame.
          # Asking that frame for its deepest message can descend once more into a
          # message-less MethodTraceException and restore an outer frame by mistake.
          raw_message = primary.message.to_s
          raw_message = "#{ex.class.name} (no message)" if raw_message.blank?
          message = DiagnosticMessage.render(raw_message)

          file = true_filename(primary)

          range = if source && file == source.path
                    missing_require?(raw_message) ? source.require_path_range_at(line, column) : source.token_range_at(line, column, reported_size)
                  end
          size = range ? range.length : {reported_size, 1}.max
          line = range.try(&.line) || line
          column = range.try(&.column) || column

          code = primary.is_a?(::Crystal::SyntaxException) ? Diagnostics::FRONT_SYNTAX : Diagnostics::FRONT_TYPE
          Diagnostic.new(
            Diagnostic::Origin::Frontend,
            primary.warning? ? Diagnostic::Severity::Warning : Diagnostic::Severity::Error,
            code,
            message,
            file,
            line,
            column,
            size,
            detail: ex.to_s,
            range: range
          )
        end

        private def self.true_filename(ex : ::Crystal::CodeError) : String?
          ex.true_filename
        rescue
          nil
        end

        # Crystal wraps an actionable type error in one frame per instantiated
        # caller. Diagnostics point at the deepest source-located error while
        # their detail retains the complete trace.
        private def self.primary_error(ex : ::Crystal::CodeError) : ::Crystal::CodeError
          current = ex
          while current.is_a?(::Crystal::TypeException)
            inner = current.inner
            break unless inner.is_a?(::Crystal::TypeException) || inner.is_a?(::Crystal::SyntaxException)
            current = inner
          end
          current
        end

        # Keep this deliberately narrow: Crystal's diagnostic spelling identifies
        # a failed require, and Source::File verifies the reported location is a
        # `require` statement before recovering its path literal.
        private def self.missing_require?(message : String) : Bool
          message.starts_with?("can't find file ")
        end
      end
    end
  end
end
