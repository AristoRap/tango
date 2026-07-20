module Tango
  module Frontend
    # Crystal-free handoff from source discovery or semantic translation to
    # Tango's owned compiler core. Graph failures and syntax-only editor
    # requests leave program empty while retaining diagnostics and surface
    # data. A later semantic-bundle codec will materialize this same contract
    # across a process boundary.
    class Result
      getter source : Source::CompilationUnit
      getter program : IR::NIR::Program?
      getter diagnostics : Array(Diagnostic)
      getter syntax_surface : SyntaxSurface::Index

      def initialize(
        @source : Source::CompilationUnit,
        @program : IR::NIR::Program? = nil,
        @diagnostics : Array(Diagnostic) = [] of Diagnostic,
        @syntax_surface : SyntaxSurface::Index = SyntaxSurface::Index.new,
      )
      end

      def ok? : Bool
        !@program.nil? && @diagnostics.none? { |diagnostic| diagnostic.severity.error? }
      end
    end
  end
end
