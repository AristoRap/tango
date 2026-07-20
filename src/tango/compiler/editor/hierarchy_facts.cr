module Tango
  module Compiler
    module Editor
      class Index
        # Source-owned hierarchy items and compiler-proven direct relations.
        # These values are the complete request-facing projection: handlers do
        # not need NIR, analysis tables, or Crystal compiler objects.
        class HierarchyFacts
          enum ItemKind
            Class
            Struct
            Capability
          end

          enum RelationKind
            Superclass
            Capability
          end

          enum Completeness
            Exact
            ReachedPartial
          end

          record Key, type : IR::Type, declaration : Source::Range
          record Item,
            key : Key,
            name : String,
            kind : ItemKind,
            range : Source::Range,
            selection_range : Source::Range
          record Relation,
            subtype : Key,
            supertype : Key,
            kind : RelationKind,
            completeness : Completeness

          getter items : Array(Item)
          getter relations : Array(Relation)

          def initialize(
            @items : Array(Item) = [] of Item,
            @relations : Array(Relation) = [] of Relation,
          )
          end
        end
      end
    end
  end
end
