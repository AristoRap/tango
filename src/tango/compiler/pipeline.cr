module Tango
  module Compiler
    class Pipeline
      getter current_snapshot : Snapshot?

      def nir : IR::NIR::Program?
        current_snapshot.try(&.nir)
      end

      def facts : Analysis::Facts::Table?
        current_snapshot.try(&.facts)
      end

      def plans : Planning::Plans::Table?
        current_snapshot.try(&.plans)
      end

      def lir : IR::LIR::Program?
        current_snapshot.try(&.lir)
      end

      def go : Target::Go::IR::File?
        current_snapshot.try(&.target_ir)
      end

      def snapshot(
        source : String,
        filename : String = "source.tn",
        resolver : Frontend::SourceGraph::Resolver = Frontend::SourceGraph::DISK_RESOLVER,
        stable_path : Bool = true,
        profile : CompilationProfile = CompilationProfile::Development,
      ) : Snapshot
        compile_loaded(source, filename, resolver, profile, pre_target: false, stable_path: stable_path)
      end

      def pre_target_snapshot(
        source : String,
        filename : String = "source.tn",
        resolver : Frontend::SourceGraph::Resolver = Frontend::SourceGraph::DISK_RESOLVER,
        stable_path : Bool = true,
        profile : CompilationProfile = CompilationProfile::Development,
      ) : Snapshot
        compile_loaded(source, filename, resolver, profile, pre_target: true, stable_path: stable_path)
      end

      # Parse and resolve only the current source graph. Editor edits use this
      # cheap current-text projection while semantic analysis runs elsewhere.
      def editor_surface_snapshot(
        source : String,
        filename : String = "source.tn",
        resolver : Frontend::SourceGraph::Resolver = Frontend::SourceGraph::DISK_RESOLVER,
        stable_path : Bool = true,
      ) : Snapshot
        entrypoint = source_file(source, filename, stable_path)
        remember(Driver.editor_surface(entrypoint, resolver))
      end

      def compile(source : String, filename : String = "source.tn", profile : CompilationProfile = CompilationProfile::Development) : String
        built = snapshot(source, filename, profile: profile)
        built.go_source || raise built.diagnostics.map(&.to_s).join('\n')
      end

      private def compile_loaded(
        source : String,
        filename : String,
        resolver : Frontend::SourceGraph::Resolver,
        profile : CompilationProfile,
        pre_target : Bool,
        stable_path : Bool,
      ) : Snapshot
        entrypoint = source_file(source, filename, stable_path)
        built = pre_target ? Driver.pre_target(entrypoint, resolver, profile) : Driver.run(entrypoint, resolver, profile)
        remember(built)
      end

      private def remember(built : Snapshot) : Snapshot
        @current_snapshot = built
        built
      end

      private def source_file(source : String, filename : String, stable_path : Bool) : Source::File
        Source::File.canonical(filename, source, stable_path)
      end
    end
  end
end
