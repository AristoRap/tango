module Tango
  module Frontend
    # Resolves local Tango source before Crystal semantics. The resolver is the
    # only IO seam: production uses DISK_RESOLVER and specs can inject a pure
    # in-memory implementation.
    module SourceGraph
      alias Resolver = Proc(String, Source::File, Array(Source::File))

      # One local-path contract serves disk builds and editor overlays. Open
      # buffers replace content only; request validation, extension handling,
      # path expansion, and canonical identity stay identical.
      class LocalResolver
        def initialize(
          overlays : Hash(String, String) = {} of String => String,
          @bundled_root : String = Workspace::Layout.bundled_packages_dir,
        )
          @overlays = {} of String => Source::File
          overlays.each do |path, text|
            expanded = ::File.expand_path(path)
            canonical = identity(expanded)
            @overlays[canonical] = Source::File.new(expanded, text, canonical)
          end
        end

        def to_resolver : Resolver
          Resolver.new { |request, from| resolve(request, from) }
        end

        private def resolve(request : String, from : Source::File) : Array(Source::File)
          requested = requested_path(request)
          base = if SourceGraph.bundled_request?(request)
                   @bundled_root
                 elsif SourceGraph.relative_request?(request)
                   ::File.dirname(from.path)
                 else
                   return [] of Source::File
                 end
          pattern = ::File.expand_path(requested, dir: base)
          if glob?(request)
            return glob_files(pattern)
          end

          file_at(pattern).try { |file| [file] } || [] of Source::File
        end

        private def glob_files(pattern : String) : Array(Source::File)
          paths = Dir.glob(pattern).select { |path| ::File.file?(path) }
          @overlays.each_value do |file|
            paths << file.path if ::File.match?(pattern, file.path)
          end

          seen = Set(String).new
          paths.sort!.compact_map do |path|
            canonical = identity(path)
            next unless seen.add?(canonical)

            @overlays[canonical]? || disk_file(path, canonical)
          end
        end

        private def file_at(path : String) : Source::File?
          canonical = identity(path)
          @overlays[canonical]? || disk_file(path, canonical)
        end

        private def disk_file(path : String, canonical : String) : Source::File?
          return unless ::File.file?(path)

          Source::File.new(path, ::File.read(path), canonical)
        end

        private def glob?(request : String) : Bool
          request.includes?('*')
        end

        private def requested_path(request : String) : String
          return "#{request}/*.tn" if request.ends_with?("/**")

          request.ends_with?(".tn") ? request : "#{request}.tn"
        end

        private def identity(path : String) : String
          Source::File.canonical_identity(path)
        end
      end

      def self.resolver(
        overlays : Hash(String, String) = {} of String => String,
        bundled_root : String = Workspace::Layout.bundled_packages_dir,
      ) : Resolver
        LocalResolver.new(overlays, bundled_root).to_resolver
      end

      def self.relative_request?(request : String) : Bool
        request.starts_with?("./") || request.starts_with?("../")
      end

      def self.bundled_request?(request : String) : Bool
        return false unless request.starts_with?("tango/")
        return false if request.includes?('*')

        segments = request.split('/')
        segments.size > 1 && segments.all? { |segment| !segment.empty? && segment != "." && segment != ".." }
      end

      DISK_RESOLVER = resolver

      class Loader
        private class GraphState
          getter files = [] of Source::File
          getter requires = [] of Source::RequireDirective
          getter edges = [] of Source::RequireEdge
          getter diagnostics = [] of Diagnostic
          getter seen = Set(String).new
        end

        def self.load(entrypoint : Source::File, resolver : Resolver) : Frontend::Result
          new(entrypoint, resolver).load
        end

        def initialize(@entrypoint : Source::File, @resolver : Resolver)
          @state = GraphState.new
        end

        def load : Frontend::Result
          @state.seen << @entrypoint.identity
          scan(@entrypoint)
          @state.files << @entrypoint
          unit = Source::CompilationUnit.new(@state.files, @entrypoint, @state.requires, @state.edges)
          Frontend::Result.new(unit, diagnostics: @state.diagnostics)
        end

        private def scan(file : Source::File) : Nil
          directives(file).each do |node|
            range = directive_range(file, node)
            request = node.string
            @state.requires << Source::RequireDirective.new(file.path, request, range)

            unless SourceGraph.relative_request?(request) || SourceGraph.bundled_request?(request)
              @state.diagnostics << require_diagnostic(
                file,
                range,
                "Tango requires must use a relative path (`./x` or `../x`) or a bundled package (`tango/x`)"
              )
              next
            end

            unless tango_extension?(request)
              @state.diagnostics << require_diagnostic(
                file,
                range,
                "Tango requires resolve `.tn` files; remove the foreign extension from #{request.inspect}"
              )
              next
            end

            unless file.stable_path?
              @state.diagnostics << require_diagnostic(
                file,
                range,
                "relative requires from stdin need a named entry file"
              )
              next
            end

            resolved = begin
              @resolver.call(request, file)
            rescue ex : File::Error
              @state.diagnostics << require_diagnostic(file, range, "couldn't read required source '#{request}': #{ex.message}")
              next
            end
            if resolved.empty?
              message = glob?(request) ? "require glob '#{request}' matched no `.tn` files" : "can't find file '#{request}'"
              @state.diagnostics << require_diagnostic(file, range, message)
              next
            end

            resolved.each do |dependency|
              @state.edges << Source::RequireEdge.new(file.path, request, dependency.path, range)
              next unless @state.seen.add?(dependency.identity)

              scan(dependency)
              @state.files << dependency
            end
          end
        rescue ex : ::Crystal::CodeError
          @state.diagnostics << Crystal::DiagnosticTranslator.from(ex, file)
        end

        private def directives(file : Source::File) : Array(::Crystal::Require)
          root = Crystal::Semantic.parse(file.code, file.path)
          nodes = root.is_a?(::Crystal::Expressions) ? root.expressions : [root] of ::Crystal::ASTNode
          nodes.compact_map(&.as?(::Crystal::Require))
        end

        private def directive_range(file : Source::File, node : ::Crystal::Require) : Source::Range
          location = node.location
          finish = node.end_location
          return file.range_at(1, 1) unless location && finish

          start_offset = file.line_index.byte_offset_at(location.line_number, location.column_number)
          end_offset = file.line_index.byte_offset_at(finish.line_number, finish.column_number) + 1
          Source::Range.new(
            file.path,
            start_offset,
            end_offset.clamp(start_offset, file.code.bytesize),
            location.line_number,
            location.column_number
          )
        end

        private def require_diagnostic(file : Source::File, directive : Source::Range, message : String) : Diagnostic
          range = file.require_path_range_at(directive.line || 1, directive.column || 1) || directive
          Diagnostic.new(
            Diagnostic::Origin::Frontend,
            Diagnostic::Severity::Error,
            Diagnostics::FRONT_REQUIRE,
            message,
            file: file.path,
            line: range.line || 1,
            column: range.column || 1,
            size: range.length,
            range: range
          )
        end

        private def tango_extension?(request : String) : Bool
          extension = ::File.extname(request)
          extension.empty? || extension == ".tn"
        end

        private def glob?(request : String) : Bool
          request.includes?('*')
        end
      end
    end
  end
end
