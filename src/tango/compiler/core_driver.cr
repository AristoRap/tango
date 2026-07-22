module Tango
  module Compiler
    # Runs only Tango-owned compiler phases over a Crystal-free frontend
    # result. This is the in-process predecessor of the self-hosted core's
    # versioned semantic-bundle entrypoint.
    class CoreDriver
      enum Depth
        PreTarget
        Full
      end

      def self.run(
        frontend : Frontend::Result,
        profile : CompilationProfile = CompilationProfile::Development,
        depth : Depth = Depth::Full,
      ) : Snapshot
        new(frontend, profile).run(depth)
      end

      def initialize(@frontend : Frontend::Result, @profile : CompilationProfile = CompilationProfile::Development)
      end

      def run(depth : Depth = Depth::Full) : Snapshot
        source = @frontend.source
        syntax_surface = @frontend.syntax_surface
        nir = @frontend.program
        unless nir
          return Snapshot.new(
            source: source,
            diagnostics: @frontend.diagnostics,
            editor_index: Editor::Index.from(nil, nil, syntax_surface),
            syntax_surface: syntax_surface
          )
        end

        nir = Expansion::Driver.run(nir)
        facts = Analysis::Driver.run(nir)
        editor_index = Editor::Index.from(nir, facts, syntax_surface)
        lint_diagnostics = Lint.run(facts, editor_index)
        diagnostics = @frontend.diagnostics + lint_diagnostics
        plans = Planning::Driver.run(nir, facts, @profile)
        lir = Lowering::ToLIR.translate(nir, facts, plans)

        unsupported = IR::LIR.unsupported_reasons(lir)
        unless unsupported.empty?
          unsupported_diagnostics = unsupported.map do |reason|
            loc = reason.loc
            range = loc.try do |source_loc|
              source.files.find { |file| file.path == source_loc.file }.try do |file|
                file.range_at(source_loc.line, source_loc.column)
              end
            end
            Diagnostic.new(
              Diagnostic::Origin::Emit,
              Diagnostic::Severity::Error,
              Diagnostics::EMIT_UNSUPPORTED,
              reason.message,
              file: loc.try(&.file),
              line: loc.try(&.line) || 1,
              column: loc.try(&.column) || 1,
              range: range
            )
          end
          return Snapshot.new(
            source: source,
            nir: nir,
            facts: facts,
            plans: plans,
            lir: lir,
            diagnostics: diagnostics + unsupported_diagnostics,
            editor_index: editor_index,
            syntax_surface: syntax_surface
          )
        end

        if depth.pre_target?
          return Snapshot.new(
            source: source,
            nir: nir,
            facts: facts,
            plans: plans,
            lir: lir,
            diagnostics: diagnostics,
            editor_index: editor_index,
            syntax_surface: syntax_surface
          )
        end

        target_ir = Target::Go::FromLIR.translate(lir)
        requirements = Target::Go::Runtime::Requirement.closure(target_ir.requirements)
        go_modules = requirements.compact_map(&.as?(Target::Go::Runtime::ModuleRequirement))
        begin
          go_source = Target::Go::Source.emit(target_ir)
        rescue ex : Target::Go::Source::ImportConflict
          target_diagnostic = Diagnostic.new(
            Diagnostic::Origin::Emit,
            Diagnostic::Severity::Error,
            Diagnostics::EMIT_UNSUPPORTED,
            ex.message || "incompatible Go imports"
          )
          return Snapshot.new(
            source: source,
            nir: nir,
            facts: facts,
            plans: plans,
            lir: lir,
            target_ir: target_ir,
            go_modules: go_modules,
            diagnostics: diagnostics + [target_diagnostic],
            editor_index: editor_index,
            syntax_surface: syntax_surface
          )
        end

        Snapshot.new(
          source: source,
          nir: nir,
          facts: facts,
          plans: plans,
          lir: lir,
          target_ir: target_ir,
          go_source: go_source,
          go_modules: go_modules,
          diagnostics: diagnostics,
          editor_index: editor_index,
          syntax_surface: syntax_surface
        )
      end
    end
  end
end
