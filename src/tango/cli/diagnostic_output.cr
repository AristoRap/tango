module Tango
  module CLI
    # Shared terminal projection for every command that consumes compiler or
    # toolchain diagnostics. Diagnostics remain data until this CLI boundary.
    module DiagnosticOutput
      def self.render(snapshot : Compiler::Snapshot, error : IO) : Nil
        render(snapshot.source, snapshot.diagnostics, error)
      end

      def self.render(source : SourceInput::Entry, diagnostics : Array(Diagnostic), error : IO) : Nil
        render(Source::CompilationUnit.single(source.to_source), diagnostics, error)
      end

      def self.render(source : Source::CompilationUnit, diagnostics : Array(Diagnostic), error : IO) : Nil
        color = error.tty? && ENV["NO_COLOR"]?.nil?
        diagnostics.each do |diagnostic|
          file = diagnostic.file.try { |path| source.file?(path) }
          unless file
            error.puts diagnostic
            next
          end

          error.puts Diagnostics::Renderer.render(
            file.code,
            diagnostic,
            path: file.path,
            color: color,
            index: file.line_index
          )
        end
      end
    end
  end
end
