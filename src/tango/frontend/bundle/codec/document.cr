module Tango
  module Frontend
    module Bundle
      # Canonical schema-v1 JSON transport. Shared value families delegate to
      # Transport's strict generated data; only bundle framing and NIR remain
      # explicit compatibility mappings here.
      module Codec
        extend self

        TOP_LEVEL_FIELDS = %w(
          schema_version
          frontend_version
          prelude_version
          source_table
          normalized_nir
          syntax_surface
          frontend_diagnostics
          source_provenance
        )

        def dump(document : Document) : String
          JSON.build do |builder|
            builder.object do
              builder.field("schema_version", document.schema_version)
              builder.field("frontend_version", document.frontend_version)
              builder.field("prelude_version", document.prelude_version)
              builder.field("source_table") do
                builder.array { document.source_table.each { |source| write_source(builder, source) } }
              end
              builder.field("normalized_nir") do
                Value.write_nullable(builder, document.normalized_nir) do |program|
                  NirEncoder.write_program(builder, program)
                end
              end
              builder.field("syntax_surface") { Transport::SurfaceData.new(document.syntax_surface).to_json(builder) }
              builder.field("frontend_diagnostics") do
                builder.array do
                  document.frontend_diagnostics.each do |diagnostic|
                    Transport::DiagnosticData.new(diagnostic).to_json(builder)
                  end
                end
              end
              builder.field("source_provenance") { write_provenance(builder, document.source_provenance) }
            end
          end
        end

        def load(source : String) : Document
          root = JSON.parse(source)
          object = Value.object(root, "$")
          version = Value.int32(Value.required(object, "schema_version", "$"), "$.schema_version")
          unless version == Document::CURRENT_SCHEMA_VERSION
            raise UnsupportedVersionError.new(version, Document::CURRENT_SCHEMA_VERSION)
          end

          Value.expect_keys(object, TOP_LEVEL_FIELDS, "$")
          read_document(object)
        rescue error : UnsupportedVersionError | CodecError
          raise error
        rescue error : JSON::ParseException
          raise CodecError.new("$", error.message || "malformed JSON")
        rescue error
          raise CodecError.new("$", error.message || error.class.name)
        end

        private def read_document(object : Hash(String, JSON::Any)) : Document
          sources = Value.array(field(object, "source_table", "$"), "$.source_table").map_with_index do |source, index|
            file = Value.read_data(source, "$.source_table[#{index}]", Transport::FileData).to_file
            Source.from(file)
          end
          program = Value.optional(field(object, "normalized_nir", "$")) do |nir|
            NirDecoder.read_program(nir, "$.normalized_nir")
          end
          diagnostics = Value.array(field(object, "frontend_diagnostics", "$"), "$.frontend_diagnostics").map_with_index do |diagnostic, index|
            Value.read_data(
              diagnostic,
              "$.frontend_diagnostics[#{index}]",
              Transport::DiagnosticData
            ).to_diagnostic
          end
          provenance = read_provenance(field(object, "source_provenance", "$"), "$.source_provenance")
          unless provenance.entrypoint_index.in?(0...sources.size)
            Value.invalid(
              "$.source_provenance.entrypoint_index",
              "index #{provenance.entrypoint_index} is outside the source table"
            )
          end

          Document.new(
            schema_version: Value.int32(field(object, "schema_version", "$"), "$.schema_version"),
            frontend_version: Value.string(field(object, "frontend_version", "$"), "$.frontend_version"),
            prelude_version: Value.string(field(object, "prelude_version", "$"), "$.prelude_version"),
            source_table: sources,
            normalized_nir: program,
            syntax_surface: Value.read_data(
              field(object, "syntax_surface", "$"),
              "$.syntax_surface",
              Transport::SurfaceData
            ).to_surface,
            frontend_diagnostics: diagnostics,
            source_provenance: provenance
          )
        end

        private def write_source(builder, source : Source) : Nil
          Transport::FileData.new(source.to_source).to_json(builder)
        end

        private def write_provenance(builder, provenance : Provenance) : Nil
          builder.object do
            builder.field("entrypoint_index", provenance.entrypoint_index)
            builder.field("requires") do
              builder.array do
                provenance.requires.each { |directive| Transport::RequireData.new(directive).to_json(builder) }
              end
            end
            builder.field("edges") do
              builder.array { provenance.edges.each { |edge| Transport::EdgeData.new(edge).to_json(builder) } }
            end
          end
        end

        private def read_provenance(value, location) : Provenance
          object = Value.object(value, location)
          Value.expect_keys(object, %w(entrypoint_index requires edges), location)
          requires = Value.array(field(object, "requires", location), "#{location}.requires").map_with_index do |directive, index|
            Value.read_data(
              directive,
              "#{location}.requires[#{index}]",
              Transport::RequireData
            ).to_directive
          end
          edges = Value.array(field(object, "edges", location), "#{location}.edges").map_with_index do |edge, index|
            Value.read_data(edge, "#{location}.edges[#{index}]", Transport::EdgeData).to_edge
          end
          Provenance.new(
            Value.int32(field(object, "entrypoint_index", location), "#{location}.entrypoint_index"),
            requires,
            edges
          )
        end

        private def field(object, key, location) : JSON::Any
          Value.required(object, key, location)
        end
      end
    end
  end
end
