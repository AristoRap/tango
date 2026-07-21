module Tango
  module Compiler
    module Editor
      class Index
        private def build_hierarchy(program : IR::NIR::Program, facts : Analysis::Facts::Table?) : Nil
          items = source_type_items(program)
          add_witnessed_capability_items(items, facts) if facts
          relations = source_superclass_relations(program, items)
          relations.concat(capability_relations(items, facts)) if facts

          items.sort_by! { |item| hierarchy_item_order(item) }
          relations = relations.uniq.sort_by do |relation|
            {relation.subtype.type.to_s, relation.supertype.type.to_s, relation.kind.to_s}
          end
          @hierarchy = HierarchyFacts.new(items, relations)
        end

        private def source_type_items(program : IR::NIR::Program) : Array(HierarchyFacts::Item)
          items = IR::NIR::Walk.children(program).compact_map do |stmt|
            next unless stmt.is_a?(IR::NIR::Class)
            selection = stmt.name_span
            next unless selection
            surface = @syntax_surface.declaration_at(selection)
            next unless surface && (surface.kind.class? || surface.kind.struct?)
            kind = stmt.reference? ? HierarchyFacts::ItemKind::Class : HierarchyFacts::ItemKind::Struct
            hierarchy_item(stmt.concrete_type, surface, kind)
          end

          @syntax_surface.declarations.each do |surface|
            next unless surface.kind.module?
            add_hierarchy_item(
              items,
              hierarchy_item(IR::Type.klass(qualified_surface_name(surface)), surface, HierarchyFacts::ItemKind::Capability)
            )
          end
          items
        end

        private def add_witnessed_capability_items(
          items : Array(HierarchyFacts::Item),
          facts : Analysis::Facts::Table,
        ) : Nil
          facts.capability_conformances.each_value do |witnesses|
            witnesses.each do |witness|
              next if hierarchy_item_for(items, witness.capability)
              surface = source_type_surface(witness.capability, module_only: true)
              next unless surface
              add_hierarchy_item(
                items,
                hierarchy_item(witness.capability, surface, HierarchyFacts::ItemKind::Capability)
              )
            end
          end
        end

        private def source_superclass_relations(
          program : IR::NIR::Program,
          items : Array(HierarchyFacts::Item),
        ) : Array(HierarchyFacts::Relation)
          IR::NIR::Walk.children(program).compact_map do |stmt|
            next unless stmt.is_a?(IR::NIR::Class)
            superclass = stmt.superclass_type
            next unless superclass
            subtype = hierarchy_item_for(items, stmt.concrete_type)
            supertype = hierarchy_item_for(items, superclass)
            next unless subtype && supertype
            HierarchyFacts::Relation.new(
              subtype.key,
              supertype.key,
              HierarchyFacts::RelationKind::Superclass,
              HierarchyFacts::Completeness::Exact
            )
          end
        end

        private def capability_relations(
          items : Array(HierarchyFacts::Item),
          facts : Analysis::Facts::Table,
        ) : Array(HierarchyFacts::Relation)
          facts.capability_conformances.values.flat_map do |witnesses|
            witnesses.compact_map do |witness|
              subtype = hierarchy_item_for(items, witness.concrete)
              supertype = hierarchy_item_for(items, witness.capability)
              next unless subtype && supertype
              HierarchyFacts::Relation.new(
                subtype.key,
                supertype.key,
                HierarchyFacts::RelationKind::Capability,
                HierarchyFacts::Completeness::ReachedPartial
              )
            end
          end
        end

        private def hierarchy_item(
          type : IR::Type,
          surface : Frontend::SyntaxSurface::Declaration,
          kind : HierarchyFacts::ItemKind,
        ) : HierarchyFacts::Item
          key = HierarchyFacts::Key.new(type, surface.selection_range)
          HierarchyFacts::Item.new(key, type.to_semantic_s, kind, surface.range, surface.selection_range)
        end

        private def add_hierarchy_item(items : Array(HierarchyFacts::Item), item : HierarchyFacts::Item) : Nil
          items << item unless items.any?(&.key.==(item.key))
        end

        private def hierarchy_item_for(
          items : Array(HierarchyFacts::Item),
          type : IR::Type,
        ) : HierarchyFacts::Item?
          items.find(&.key.type.==(type))
        end

        private def source_type_surface(
          type : IR::Type,
          module_only : Bool = false,
        ) : Frontend::SyntaxSurface::Declaration?
          name = type.name
          return unless name
          @syntax_surface.declarations.find do |surface|
            type_kind = surface.kind.module? || (!module_only && (surface.kind.class? || surface.kind.struct?))
            type_kind && qualified_surface_name(surface) == name
          end
        end

        private def qualified_surface_name(surface : Frontend::SyntaxSurface::Declaration) : String
          surface.container ? "#{surface.container}::#{surface.name}" : surface.name
        end

        private def hierarchy_item_order(item : HierarchyFacts::Item)
          range = item.selection_range
          {item.name, range.path, range.start_offset, item.key.type.to_s, item.kind.to_s}
        end
      end
    end
  end
end
