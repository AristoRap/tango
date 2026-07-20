module Tango
  module Frontend
    module Crystal
      # Owns the Crystal-specific half of compilation and exports only neutral
      # Tango data.
      class Driver
        def self.run(source : Source::CompilationUnit) : Frontend::Result
          new(source).run
        end

        def self.surface(
          source : Source::CompilationUnit,
          diagnostics : Array(Diagnostic) = [] of Diagnostic,
        ) : Frontend::Result
          new(source).surface(diagnostics)
        end

        def initialize(@source : Source::CompilationUnit)
          @syntax_surface = SyntaxSurfaceBuilder.build(@source)
        end

        def run : Frontend::Result
          semantic = compile_semantic
          return semantic unless semantic.is_a?(::Crystal::Compiler::Result)

          required_file_diagnostics = RequiredFileCheck.run(semantic.node, @source)
          return failed(required_file_diagnostics) unless required_file_diagnostics.empty?

          internal_diagnostics = @source.files.flat_map do |file|
            # Bundled packages are trusted language-library source. Their
            # reserved leaves remain unavailable to applications because calls
            # from application files still pass through this check.
            next [] of Diagnostic if Workspace::Layout.bundled_package_path?(file.path)

            surface = Semantic.parse(file.code, file.path)
            InternalCheck.run(semantic.program, semantic.node, surface, file)
          end
          return failed(internal_diagnostics) unless internal_diagnostics.empty?

          Frontend::Result.new(
            @source,
            program: ToNIR.translate(semantic, @source),
            syntax_surface: @syntax_surface
          )
        end

        # Syntax-only and source-graph failure requests cross the same neutral
        # handoff as semantic compilation; only the optional program differs.
        def surface(diagnostics : Array(Diagnostic) = [] of Diagnostic) : Frontend::Result
          Frontend::Result.new(
            @source,
            diagnostics: diagnostics,
            syntax_surface: @syntax_surface
          )
        end

        private def compile_semantic : ::Crystal::Compiler::Result | Frontend::Result
          Semantic.compile(@source)
        rescue ex : Toolchain::Crystal::SetupError
          failed([
            Diagnostic.new(
              Diagnostic::Origin::Check,
              Diagnostic::Severity::Error,
              Diagnostics::CHECK_CRYSTAL_PATH,
              ex.message.to_s
            ),
          ])
        rescue ex : ::Crystal::CodeError
          failed([DiagnosticTranslator.from(ex, @source)])
        end

        private def failed(diagnostics : Array(Diagnostic)) : Frontend::Result
          Frontend::Result.new(
            @source,
            diagnostics: diagnostics,
            syntax_surface: @syntax_surface
          )
        end
      end
    end
  end
end
