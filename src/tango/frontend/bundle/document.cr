module Tango
  module Frontend
    module Bundle
      # One source-table row. Line indexes are derived from code when the table
      # is materialized, so the boundary does not duplicate them.
      record Source,
        path : String,
        code : String,
        identity : String,
        stable_path : Bool do
        def self.from(source : Tango::Source::File) : self
          new(source.path, source.code, source.identity, source.stable_path?)
        end

        def to_source : Tango::Source::File
          Tango::Source::File.new(@path, @code, @identity, @stable_path)
        end
      end

      # Source-graph facts that cannot be recovered from source text alone.
      # The entrypoint is an index so duplicate display paths stay unambiguous.
      record Provenance,
        entrypoint_index : Int32,
        requires : Array(Tango::Source::RequireDirective),
        edges : Array(Tango::Source::RequireEdge)

      # Versioned, target-neutral process-boundary document around the current
      # Frontend::Result. Wire codecs map these fields explicitly.
      class Document
        CURRENT_SCHEMA_VERSION = 1

        getter schema_version : Int32
        getter frontend_version : String
        getter prelude_version : String
        getter source_table : Array(Source)
        getter normalized_nir : IR::NIR::Program?
        getter syntax_surface : SyntaxSurface::Index
        getter frontend_diagnostics : Array(Diagnostic)
        getter source_provenance : Provenance

        def self.from(
          result : Result,
          frontend_version : String,
          prelude_version : String,
        ) : self
          source = result.source
          entrypoint_index = source.files.index(source.entrypoint) || raise ArgumentError.new(
            "frontend result entrypoint is absent from its source table"
          )

          new(
            schema_version: CURRENT_SCHEMA_VERSION,
            frontend_version: frontend_version,
            prelude_version: prelude_version,
            source_table: source.files.map { |file| Source.from(file) },
            normalized_nir: result.program,
            syntax_surface: result.syntax_surface,
            frontend_diagnostics: result.diagnostics,
            source_provenance: Provenance.new(
              entrypoint_index,
              source.requires.dup,
              source.edges.dup
            )
          )
        end

        def initialize(
          @schema_version : Int32,
          @frontend_version : String,
          @prelude_version : String,
          source_table : Array(Source),
          @normalized_nir : IR::NIR::Program?,
          syntax_surface : SyntaxSurface::Index,
          frontend_diagnostics : Array(Diagnostic),
          source_provenance : Provenance,
        )
          unless @schema_version == CURRENT_SCHEMA_VERSION
            raise UnsupportedVersionError.new(@schema_version, CURRENT_SCHEMA_VERSION)
          end

          unless source_provenance.entrypoint_index.in?(0...source_table.size)
            raise ArgumentError.new(
              "semantic bundle entrypoint index #{source_provenance.entrypoint_index} is outside its source table"
            )
          end

          @source_table = source_table.dup
          @syntax_surface = SyntaxSurface::Index.new(
            syntax_surface.declarations.dup,
            syntax_surface.scopes.dup
          )
          @frontend_diagnostics = frontend_diagnostics.dup
          @source_provenance = Provenance.new(
            source_provenance.entrypoint_index,
            source_provenance.requires.dup,
            source_provenance.edges.dup
          )
        end

        def to_frontend_result : Result
          files = @source_table.map(&.to_source)
          entrypoint = files[@source_provenance.entrypoint_index]? || raise ArgumentError.new(
            "semantic bundle entrypoint is absent from its source table"
          )
          source = Tango::Source::CompilationUnit.new(
            files,
            entrypoint,
            @source_provenance.requires.dup,
            @source_provenance.edges.dup
          )

          Result.new(
            source,
            program: @normalized_nir,
            diagnostics: @frontend_diagnostics.dup,
            syntax_surface: SyntaxSurface::Index.new(
              @syntax_surface.declarations.dup,
              @syntax_surface.scopes.dup
            )
          )
        end
      end
    end
  end
end
