module Tango
  module Compiler
    class Snapshot
      getter source : Source::CompilationUnit
      getter nir : IR::NIR::Program?
      getter facts : Analysis::Facts::Table?
      getter plans : Planning::Plans::Table?
      getter lir : IR::LIR::Program?
      getter target_ir : Target::Go::IR::File?
      getter go_source : String?
      getter diagnostics : Array(Diagnostic)
      getter editor_index : Editor::Index
      getter syntax_surface : Frontend::SyntaxSurface::Index
      getter? editor_semantic : Bool

      def initialize(
        @source : Source::CompilationUnit,
        @nir : IR::NIR::Program? = nil,
        @facts : Analysis::Facts::Table? = nil,
        @plans : Planning::Plans::Table? = nil,
        @lir : IR::LIR::Program? = nil,
        @target_ir : Target::Go::IR::File? = nil,
        @go_source : String? = nil,
        @diagnostics : Array(Diagnostic) = [] of Diagnostic,
        @editor_index : Editor::Index = Editor::Index.new,
        @syntax_surface : Frontend::SyntaxSurface::Index = Frontend::SyntaxSurface::Index.new,
        @editor_semantic : Bool = false,
      )
      end

      def semantic_ready? : Bool
        !@facts.nil? || @editor_semantic
      end

      def ok? : Bool
        @diagnostics.none? { |diagnostic| diagnostic.severity.error? }
      end
    end
  end
end
