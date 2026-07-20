module Tango
  module Compiler
    # Product-facing in-process composition of the retained Crystal frontend
    # and Tango's owned compiler core.
    class Driver
      def self.frontend_host_version : String
        ::Crystal::VERSION
      end

      def self.frontend(source : Source::CompilationUnit) : Frontend::Result
        Frontend::Crystal::Driver.run(source)
      end

      def self.frontend(
        entrypoint : Source::File,
        resolver : Frontend::SourceGraph::Resolver,
      ) : Frontend::Result
        load(entrypoint, resolver, semantic: true)
      end

      def self.run(source : Source::CompilationUnit, profile : CompilationProfile = CompilationProfile::Development) : Snapshot
        CoreDriver.run(frontend(source), profile)
      end

      def self.pre_target(source : Source::CompilationUnit, profile : CompilationProfile = CompilationProfile::Development) : Snapshot
        CoreDriver.run(frontend(source), profile, CoreDriver::Depth::PreTarget)
      end

      def self.run(
        entrypoint : Source::File,
        resolver : Frontend::SourceGraph::Resolver,
        profile : CompilationProfile = CompilationProfile::Development,
      ) : Snapshot
        CoreDriver.run(frontend(entrypoint, resolver), profile)
      end

      def self.pre_target(
        entrypoint : Source::File,
        resolver : Frontend::SourceGraph::Resolver,
        profile : CompilationProfile = CompilationProfile::Development,
      ) : Snapshot
        CoreDriver.run(frontend(entrypoint, resolver), profile, CoreDriver::Depth::PreTarget)
      end

      def self.editor_surface(
        entrypoint : Source::File,
        resolver : Frontend::SourceGraph::Resolver,
      ) : Snapshot
        frontend = load(entrypoint, resolver, semantic: false)
        CoreDriver.run(frontend, depth: CoreDriver::Depth::PreTarget)
      end

      private def self.load(
        entrypoint : Source::File,
        resolver : Frontend::SourceGraph::Resolver,
        semantic : Bool,
      ) : Frontend::Result
        loaded = Frontend::SourceGraph::Loader.load(entrypoint, resolver)
        return Frontend::Crystal::Driver.surface(loaded.source, loaded.diagnostics) unless semantic
        return Frontend::Crystal::Driver.surface(loaded.source, loaded.diagnostics) unless loaded.diagnostics.empty?

        Frontend::Crystal::Driver.run(loaded.source)
      end
    end
  end
end
