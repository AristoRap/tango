module Tango
  module Lsp
    # Cached workspace ownership derived from reverse require edges. Only a
    # unique top-level owner may lend semantic facts to a directly opened
    # dependency; shared or cyclic graphs remain explicit document roots.
    class RootOwnershipIndex
      def initialize(@log : IO)
        @owners = {} of String => Array(String)
      end

      def rebuild(roots : Enumerable(String)) : Nil
        graphs = {} of String => Set(String)
        required = Set(String).new
        paths = roots.flat_map do |root|
          Dir.glob(File.join(root, "**", "*.tn"))
        end.map { |path| Source::File.canonical_identity(path) }.uniq.sort
        resolver = Frontend::SourceGraph.resolver

        paths.each do |path|
          begin
            entrypoint = Source::File.canonical(path, File.read(path))
            loaded = Frontend::SourceGraph::Loader.load(entrypoint, resolver)
            graphs[entrypoint.identity] = loaded.source.files.map(&.identity).to_set
            loaded.source.edges.each do |edge|
              required << Source::File.canonical_identity(edge.to)
            end
          rescue ex : File::Error
            @log.puts "tango lsp ownership index skipped #{path}: #{ex.message}"
          end
        end

        owners = Hash(String, Array(String)).new { |hash, identity| hash[identity] = [] of String }
        graphs.keys.reject { |identity| required.includes?(identity) }.sort.each do |root|
          graphs[root].each { |identity| owners[identity] << root }
        end
        @owners = owners
      end

      def unique_owner?(path : String) : String?
        owners = @owners[Source::File.canonical_identity(path)]?
        owners.try { |candidates| candidates.first? if candidates.size == 1 }
      end
    end
  end
end
