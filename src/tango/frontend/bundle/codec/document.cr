module Tango
  module Frontend
    module Bundle
      # Canonical schema-v1 JSON transport. Public callers see one codec owner;
      # the subordinate modules only map the document's value families.
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
              builder.field("syntax_surface") { write_surface(builder, document.syntax_surface) }
              builder.field("frontend_diagnostics") do
                builder.array do
                  document.frontend_diagnostics.each { |diagnostic| write_diagnostic(builder, diagnostic) }
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
            read_source(source, "$.source_table[#{index}]")
          end
          program = Value.optional(field(object, "normalized_nir", "$")) do |nir|
            NirDecoder.read_program(nir, "$.normalized_nir")
          end
          diagnostics = Value.array(field(object, "frontend_diagnostics", "$"), "$.frontend_diagnostics").map_with_index do |diagnostic, index|
            read_diagnostic(diagnostic, "$.frontend_diagnostics[#{index}]")
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
            syntax_surface: read_surface(field(object, "syntax_surface", "$"), "$.syntax_surface"),
            frontend_diagnostics: diagnostics,
            source_provenance: provenance
          )
        end

        private def write_source(builder, source : Source) : Nil
          builder.object do
            builder.field("path", source.path)
            builder.field("code", source.code)
            builder.field("identity", source.identity)
            builder.field("stable_path", source.stable_path)
          end
        end

        private def read_source(value, location) : Source
          object = Value.object(value, location)
          Value.expect_keys(object, %w(path code identity stable_path), location)
          Source.new(
            Value.string(field(object, "path", location), "#{location}.path"),
            Value.string(field(object, "code", location), "#{location}.code"),
            Value.string(field(object, "identity", location), "#{location}.identity"),
            Value.bool(field(object, "stable_path", location), "#{location}.stable_path")
          )
        end

        private def write_provenance(builder, provenance : Provenance) : Nil
          builder.object do
            builder.field("entrypoint_index", provenance.entrypoint_index)
            builder.field("requires") do
              builder.array { provenance.requires.each { |directive| write_require(builder, directive) } }
            end
            builder.field("edges") do
              builder.array { provenance.edges.each { |edge| write_edge(builder, edge) } }
            end
          end
        end

        private def read_provenance(value, location) : Provenance
          object = Value.object(value, location)
          Value.expect_keys(object, %w(entrypoint_index requires edges), location)
          requires = Value.array(field(object, "requires", location), "#{location}.requires").map_with_index do |directive, index|
            read_require(directive, "#{location}.requires[#{index}]")
          end
          edges = Value.array(field(object, "edges", location), "#{location}.edges").map_with_index do |edge, index|
            read_edge(edge, "#{location}.edges[#{index}]")
          end
          Provenance.new(
            Value.int32(field(object, "entrypoint_index", location), "#{location}.entrypoint_index"),
            requires,
            edges
          )
        end

        private def write_require(builder, directive : Tango::Source::RequireDirective) : Nil
          builder.object do
            builder.field("from", directive.from)
            builder.field("request", directive.request)
            builder.field("range") { Value.write_range(builder, directive.range) }
          end
        end

        private def read_require(value, location) : Tango::Source::RequireDirective
          object = Value.object(value, location)
          Value.expect_keys(object, %w(from request range), location)
          Tango::Source::RequireDirective.new(
            Value.string(field(object, "from", location), "#{location}.from"),
            Value.string(field(object, "request", location), "#{location}.request"),
            Value.read_range(field(object, "range", location), "#{location}.range")
          )
        end

        private def write_edge(builder, edge : Tango::Source::RequireEdge) : Nil
          builder.object do
            builder.field("from", edge.from)
            builder.field("request", edge.request)
            builder.field("to", edge.to)
            builder.field("range") { Value.write_range(builder, edge.range) }
          end
        end

        private def read_edge(value, location) : Tango::Source::RequireEdge
          object = Value.object(value, location)
          Value.expect_keys(object, %w(from request to range), location)
          Tango::Source::RequireEdge.new(
            Value.string(field(object, "from", location), "#{location}.from"),
            Value.string(field(object, "request", location), "#{location}.request"),
            Value.string(field(object, "to", location), "#{location}.to"),
            Value.read_range(field(object, "range", location), "#{location}.range")
          )
        end

        private def write_surface(builder, surface : SyntaxSurface::Index) : Nil
          builder.object do
            builder.field("declarations") do
              builder.array { surface.declarations.each { |declaration| write_declaration(builder, declaration) } }
            end
            builder.field("scopes") do
              builder.array { surface.scopes.each { |scope| write_scope(builder, scope) } }
            end
          end
        end

        private def read_surface(value, location) : SyntaxSurface::Index
          object = Value.object(value, location)
          Value.expect_keys(object, %w(declarations scopes), location)
          declarations = Value.array(field(object, "declarations", location), "#{location}.declarations").map_with_index do |declaration, index|
            read_declaration(declaration, "#{location}.declarations[#{index}]")
          end
          scopes = Value.array(field(object, "scopes", location), "#{location}.scopes").map_with_index do |scope, index|
            read_scope(scope, "#{location}.scopes[#{index}]")
          end
          SyntaxSurface::Index.new(declarations, scopes)
        end

        private def write_declaration(builder, declaration : SyntaxSurface::Declaration) : Nil
          builder.object do
            builder.field("name", declaration.name)
            builder.field("kind", declaration.kind.to_s)
            builder.field("range") { Value.write_range(builder, declaration.range) }
            builder.field("selection_range") { Value.write_range(builder, declaration.selection_range) }
            write_nullable_string(builder, "container", declaration.container)
            write_nullable_string(builder, "detail", declaration.detail)
            write_nullable_string(builder, "documentation", declaration.documentation)
            write_nullable_string(builder, "explicit_type", declaration.explicit_type)
            builder.field("outline", declaration.outline)
            builder.field("visibility", declaration.visibility.to_s)
            builder.field("callable_kind") do
              Value.write_nullable(builder, declaration.callable_kind) { |kind| builder.string(kind.to_s) }
            end
            builder.field("parameters") do
              builder.array { declaration.parameters.each { |parameter| write_parameter(builder, parameter) } }
            end
            write_nullable_string(builder, "scope_id", declaration.scope_id)
          end
        end

        private def read_declaration(value, location) : SyntaxSurface::Declaration
          object = Value.object(value, location)
          Value.expect_keys(object, %w(name kind range selection_range container detail documentation explicit_type outline visibility callable_kind parameters scope_id), location)
          parameters = Value.array(field(object, "parameters", location), "#{location}.parameters").map_with_index do |parameter, index|
            read_parameter(parameter, "#{location}.parameters[#{index}]")
          end
          SyntaxSurface::Declaration.new(
            Value.string(field(object, "name", location), "#{location}.name"),
            Value.parse_enum(SyntaxSurface::DeclarationKind, field(object, "kind", location), "#{location}.kind"),
            Value.read_range(field(object, "range", location), "#{location}.range"),
            Value.read_range(field(object, "selection_range", location), "#{location}.selection_range"),
            optional_text(object, "container", location),
            optional_text(object, "detail", location),
            optional_text(object, "documentation", location),
            optional_text(object, "explicit_type", location),
            Value.bool(field(object, "outline", location), "#{location}.outline"),
            Value.parse_enum(SyntaxSurface::Visibility, field(object, "visibility", location), "#{location}.visibility"),
            optional_text(object, "callable_kind", location).try do |kind|
              Value.parse_enum_value(SyntaxSurface::CallableKind, kind, "#{location}.callable_kind")
            end,
            parameters,
            optional_text(object, "scope_id", location)
          )
        end

        private def write_parameter(builder, parameter : SyntaxSurface::Parameter) : Nil
          builder.object do
            builder.field("name", parameter.name)
            write_nullable_string(builder, "explicit_type", parameter.explicit_type)
            write_nullable_string(builder, "documentation", parameter.documentation)
          end
        end

        private def read_parameter(value, location) : SyntaxSurface::Parameter
          object = Value.object(value, location)
          Value.expect_keys(object, %w(name explicit_type documentation), location)
          SyntaxSurface::Parameter.new(
            Value.string(field(object, "name", location), "#{location}.name"),
            optional_text(object, "explicit_type", location),
            optional_text(object, "documentation", location)
          )
        end

        private def write_scope(builder, scope : SyntaxSurface::Scope) : Nil
          builder.object do
            builder.field("kind", scope.kind.to_s)
            builder.field("range") { Value.write_range(builder, scope.range) }
            write_nullable_string(builder, "container", scope.container)
            write_nullable_string(builder, "id", scope.id)
          end
        end

        private def read_scope(value, location) : SyntaxSurface::Scope
          object = Value.object(value, location)
          Value.expect_keys(object, %w(kind range container id), location)
          SyntaxSurface::Scope.new(
            Value.parse_enum(SyntaxSurface::ScopeKind, field(object, "kind", location), "#{location}.kind"),
            Value.read_range(field(object, "range", location), "#{location}.range"),
            optional_text(object, "container", location),
            optional_text(object, "id", location)
          )
        end

        private def write_diagnostic(builder, diagnostic : Diagnostic) : Nil
          builder.object do
            builder.field("origin", diagnostic.origin.to_s)
            builder.field("severity", diagnostic.severity.to_s)
            builder.field("code", diagnostic.code)
            builder.field("message", diagnostic.message)
            write_nullable_string(builder, "file", diagnostic.file)
            builder.field("line", diagnostic.line)
            builder.field("column", diagnostic.column)
            builder.field("size", diagnostic.size)
            write_nullable_string(builder, "detail", diagnostic.detail)
            builder.field("unnecessary", diagnostic.unnecessary)
            builder.field("range") do
              Value.write_nullable(builder, diagnostic.range) { |range| Value.write_range(builder, range) }
            end
            builder.field("related") do
              builder.array do
                diagnostic.related.each do |range, message|
                  builder.object do
                    builder.field("range") { Value.write_range(builder, range) }
                    builder.field("message", message)
                  end
                end
              end
            end
            builder.field("hints", diagnostic.hints)
            builder.field("fix") do
              Value.write_nullable(builder, diagnostic.fix) { |fix| write_fix(builder, fix) }
            end
          end
        end

        private def read_diagnostic(value, location) : Diagnostic
          object = Value.object(value, location)
          Value.expect_keys(object, %w(origin severity code message file line column size detail unnecessary range related hints fix), location)
          related = Value.array(field(object, "related", location), "#{location}.related").map_with_index do |item, index|
            item_location = "#{location}.related[#{index}]"
            row = Value.object(item, item_location)
            Value.expect_keys(row, %w(range message), item_location)
            {
              Value.read_range(field(row, "range", item_location), "#{item_location}.range"),
              Value.string(field(row, "message", item_location), "#{item_location}.message"),
            }
          end
          Diagnostic.new(
            Value.parse_enum(Diagnostic::Origin, field(object, "origin", location), "#{location}.origin"),
            Value.parse_enum(Diagnostic::Severity, field(object, "severity", location), "#{location}.severity"),
            Value.string(field(object, "code", location), "#{location}.code"),
            Value.string(field(object, "message", location), "#{location}.message"),
            optional_text(object, "file", location),
            Value.int32(field(object, "line", location), "#{location}.line"),
            Value.int32(field(object, "column", location), "#{location}.column"),
            Value.int32(field(object, "size", location), "#{location}.size"),
            optional_text(object, "detail", location),
            Value.bool(field(object, "unnecessary", location), "#{location}.unnecessary"),
            Value.optional(field(object, "range", location)) { |range| Value.read_range(range, "#{location}.range") },
            related,
            Value.string_array(field(object, "hints", location), "#{location}.hints"),
            Value.optional(field(object, "fix", location)) { |fix| read_fix(fix, "#{location}.fix") }
          )
        end

        private def write_fix(builder, fix : Diagnostic::Fix) : Nil
          builder.object do
            builder.field("kind", fix.kind.to_s)
            builder.field("title", fix.title)
            builder.field("edits") do
              builder.array do
                fix.edits.each do |edit|
                  builder.object do
                    builder.field("range") { Value.write_range(builder, edit.range) }
                    builder.field("new_text", edit.new_text)
                  end
                end
              end
            end
          end
        end

        private def read_fix(value, location) : Diagnostic::Fix
          object = Value.object(value, location)
          Value.expect_keys(object, %w(kind title edits), location)
          edits = Value.array(field(object, "edits", location), "#{location}.edits").map_with_index do |edit, index|
            edit_location = "#{location}.edits[#{index}]"
            row = Value.object(edit, edit_location)
            Value.expect_keys(row, %w(range new_text), edit_location)
            Tango::Source::Edit.new(
              Value.read_range(field(row, "range", edit_location), "#{edit_location}.range"),
              Value.string(field(row, "new_text", edit_location), "#{edit_location}.new_text")
            )
          end
          Diagnostic::Fix.new(
            Value.parse_enum(Diagnostic::FixKind, field(object, "kind", location), "#{location}.kind"),
            Value.string(field(object, "title", location), "#{location}.title"),
            edits
          )
        end

        private def write_nullable_string(builder, key : String, value : String?) : Nil
          builder.field(key) { Value.write_nullable(builder, value) { |text| builder.string(text) } }
        end

        private def optional_text(object, key, location) : String?
          Value.optional_string(field(object, key, location), "#{location}.#{key}")
        end

        private def field(object, key, location) : JSON::Any
          Value.required(object, key, location)
        end
      end
    end
  end
end
