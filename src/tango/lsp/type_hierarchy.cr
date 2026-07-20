module Tango
  module Lsp
    # Wire projection for protocol-neutral hierarchy facts. The containing
    # server supplies workspace/range helpers; all semantic identity stays in
    # the structured item data produced by AnalysisCodec.
    module TypeHierarchyProjection
      private alias HierarchyFacts = Compiler::Editor::Index::HierarchyFacts

      private def prepare_type_hierarchy_result(params : JSON::Any)
        resolved = resolve_position(params)
        return nil unless resolved
        items = Compiler::Editor::TypeHierarchy.prepare(
          resolved.snapshot,
          resolved.document.path,
          resolved.line,
          resolved.column
        )
        projected = items.compact_map { |item| lsp_hierarchy_item(item, resolved.snapshot) }
        projected.empty? ? nil : projected
      end

      private def type_hierarchy_supertypes_result(params : JSON::Any)
        type_hierarchy_relations_result(params, supertypes: true)
      end

      private def type_hierarchy_subtypes_result(params : JSON::Any)
        type_hierarchy_relations_result(params, supertypes: false)
      end

      private def type_hierarchy_relations_result(params : JSON::Any, supertypes : Bool)
        item = params["item"]
        uri = item["uri"]?.try(&.as_s?)
        data = item["data"]?
        return nil unless uri && data
        key = AnalysisCodec::HierarchyKeyData.from_json(data.to_json).to_key
        snapshot = @workspace.analysis_snapshot?(key.declaration.path, uri)
        return nil unless snapshot
        related = if supertypes
                    Compiler::Editor::TypeHierarchy.supertypes(snapshot, key)
                  else
                    Compiler::Editor::TypeHierarchy.subtypes(snapshot, key)
                  end
        return nil unless related
        related.compact_map do |entry|
          lsp_hierarchy_item(entry.item, snapshot, entry.kind, entry.completeness)
        end
      rescue JSON::SerializableError
        nil
      end

      private def lsp_hierarchy_item(
        item : HierarchyFacts::Item,
        snapshot : Compiler::Snapshot,
        relation : HierarchyFacts::RelationKind? = nil,
        completeness : HierarchyFacts::Completeness? = nil,
      )
        range = hierarchy_lsp_range(item.range, snapshot)
        selection = hierarchy_lsp_range(item.selection_range, snapshot)
        return nil unless range && selection
        {
          name:           item.name,
          kind:           hierarchy_symbol_kind(item.kind),
          detail:         hierarchy_detail(item.kind, relation, completeness),
          uri:            @workspace.uri_for_path(item.selection_range.path) || path_to_uri(item.selection_range.path),
          range:          range,
          selectionRange: selection,
          data:           AnalysisCodec::HierarchyKeyData.new(item.key),
        }
      end

      private def hierarchy_lsp_range(range : Source::Range, snapshot : Compiler::Snapshot) : Position::LspRange?
        current = @workspace.current_range(range, snapshot)
        return nil unless current
        source = @workspace.current_source(current.path, snapshot)
        return nil unless source
        source_index = Source::LineIndex.new(source)
        start_line, start_column = source_index.byte_line_col(current.start_offset)
        end_line, end_column = source_index.byte_line_col(current.end_offset)
        lsp_index = Position::LineIndex.new(source)
        {
          start: lsp_index.position(start_line, start_column, @position_encoding),
          end:   lsp_index.position(end_line, end_column, @position_encoding),
        }
      end

      private def hierarchy_detail(
        kind : HierarchyFacts::ItemKind,
        relation : HierarchyFacts::RelationKind?,
        completeness : HierarchyFacts::Completeness?,
      ) : String
        if relation.try(&.capability?) && completeness.try(&.reached_partial?)
          return kind.capability? ? "proven capability conformance (reached; partial)" : "reached capability implementation (partial)"
        end
        return "source-declared superclass (exact)" if relation.try(&.superclass?)
        return "capability (reached implementations only; partial)" if kind.capability?
        kind.struct? ? "struct" : "class"
      end

      private def hierarchy_symbol_kind(kind : HierarchyFacts::ItemKind) : Int32
        case kind
        in .class?      then 5  # Class
        in .struct?     then 23 # Struct
        in .capability? then 11 # Interface
        end
      end
    end
  end
end
