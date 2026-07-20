module Tango
  module Compiler
    module Editor
      # Protocol-neutral direct hierarchy queries over immutable source facts.
      # Superclass results are exact for the loaded source graph. Capability
      # results contain only implementations reached by Crystal and are partial.
      module TypeHierarchy
        alias Facts = Index::HierarchyFacts
        record Related,
          item : Facts::Item,
          kind : Facts::RelationKind,
          completeness : Facts::Completeness

        def self.prepare(snapshot : Snapshot, path : String, line : Int32, column : Int32) : Array(Facts::Item)
          file = snapshot.source.file?(path)
          return [] of Facts::Item unless file
          offset = file.line_index.byte_offset_at(line, column)
          snapshot.editor_index.hierarchy.items
            .select { |item| item.selection_range.contains?(path, offset) }
            .sort_by { |item| item_order(item) }
        end

        def self.supertypes(snapshot : Snapshot, key : Facts::Key) : Array(Related)?
          related(snapshot, key, supertypes: true)
        end

        def self.subtypes(snapshot : Snapshot, key : Facts::Key) : Array(Related)?
          related(snapshot, key, supertypes: false)
        end

        private def self.related(snapshot : Snapshot, key : Facts::Key, supertypes : Bool) : Array(Related)?
          facts = snapshot.editor_index.hierarchy
          return nil unless facts.items.any?(&.key.==(key))
          relations = facts.relations.select do |relation|
            supertypes ? relation.subtype == key : relation.supertype == key
          end
          relations.compact_map do |relation|
            related_key = supertypes ? relation.supertype : relation.subtype
            item = facts.items.find(&.key.==(related_key))
            item.try { |value| Related.new(value, relation.kind, relation.completeness) }
          end.sort_by { |entry| item_order(entry.item) }
        end

        private def self.item_order(item : Facts::Item)
          range = item.selection_range
          {item.name, range.path, range.start_offset, item.key.type.to_s, item.kind.to_s}
        end
      end
    end
  end
end
