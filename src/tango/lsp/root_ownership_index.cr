require "json"

module Tango
  module Lsp
    # Cached ownership derived only from entrypoints explicitly declared in a
    # workspace's tango.json. Directly opened dependencies may borrow semantic
    # facts from one declared owner; shared dependencies stay independent.
    class RootOwnershipIndex
      MANIFEST_NAME = "tango.json"

      def initialize(@log : IO)
        @owners = {} of String => Array(String)
      end

      def rebuild(roots : Enumerable(String)) : Nil
        graphs = {} of String => Set(String)
        roots.map { |root| Source::File.canonical_identity(root) }.uniq.sort.each do |root|
          manifest_entrypoints(root).each do |path|
            load_graph(path).try do |source_paths|
              graphs[path] = source_paths
            end
          end
        end

        owners = Hash(String, Array(String)).new { |hash, identity| hash[identity] = [] of String }
        graphs.keys.sort.each do |root|
          graphs[root].each { |identity| owners[identity] << root }
        end
        @owners = owners
      end

      def unique_owner?(path : String) : String?
        owners = @owners[Source::File.canonical_identity(path)]?
        owners.try { |candidates| candidates.first? if candidates.size == 1 }
      end

      private def manifest_entrypoints(root : String) : Array(String)
        manifest_path = File.join(root, MANIFEST_NAME)
        return [] of String unless File.file?(manifest_path)

        document = JSON.parse(File.read(manifest_path))
        object = document.as_h?
        return invalid_manifest(manifest_path, "expected a JSON object") unless object

        unknown = object.keys - ["entrypoints"]
        return invalid_manifest(manifest_path, "unknown field #{unknown.first.inspect}") unless unknown.empty?

        entries = object["entrypoints"]?.try(&.as_a?)
        return invalid_manifest(manifest_path, "expected an entrypoints array") unless entries

        seen = Set(String).new
        paths = [] of String
        entries.each_with_index do |entry, index|
          request = entry.as_s?
          return invalid_manifest(manifest_path, "entrypoints[#{index}] must be a string") unless request
          path = resolve_entrypoint(root, manifest_path, request)
          return [] of String unless path
          paths << path if seen.add?(path)
        end
        paths
      rescue ex : File::Error | JSON::ParseException
        invalid_manifest(File.join(root, MANIFEST_NAME), ex.message || ex.class.name)
      end

      private def resolve_entrypoint(root : String, manifest_path : String, request : String) : String?
        if request.empty? || Path.new(request).absolute?
          invalid_manifest(manifest_path, "entrypoint #{request.inspect} must be a relative path")
          return
        end

        path = Source::File.canonical_identity(File.expand_path(request, dir: root))
        unless inside?(path, root)
          invalid_manifest(manifest_path, "entrypoint #{request.inspect} escapes the workspace root")
          return
        end
        unless File.extname(path) == ".tn"
          invalid_manifest(manifest_path, "entrypoint #{request.inspect} must name a .tn file")
          return
        end
        unless File.file?(path)
          invalid_manifest(manifest_path, "entrypoint #{request.inspect} does not exist")
          return
        end
        path
      end

      private def inside?(path : String, root : String) : Bool
        prefix = root.ends_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
        path.starts_with?(prefix)
      end

      private def load_graph(path : String) : Set(String)?
        entrypoint = Source::File.canonical(path, File.read(path))
        loaded = Frontend::SourceGraph::Loader.load(entrypoint, Frontend::SourceGraph.resolver)
        loaded.source.files.map(&.identity).to_set
      rescue ex : File::Error
        @log.puts "tango lsp ownership index skipped #{path}: #{ex.message}"
        nil
      end

      private def invalid_manifest(path : String, message : String) : Array(String)
        @log.puts "tango lsp invalid #{path}: #{message}"
        [] of String
      end
    end
  end
end
