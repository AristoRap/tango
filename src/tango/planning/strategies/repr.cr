module Tango
  module Planning
    module Strategies
      # Chooses the representation of every union the program uses. Picks, proves
      # nothing: it reads the distinct unions Analysis collected and, per the
      # decisions log, derives each one's shape from the structured `Type`.
      #
      #   * `T?` whose non-Nil member is a reference (Go-pointer-repr) -> a bare
      #     `*T`. The predicate is "member is pointer-repr"; only classes
      #     qualify this slice, but `Channel(T)?`/`Exception?` extend it additively.
      #   * every other union -> a tagged-value carrier struct: `Nil` at
      #     tag 0 so the zero value is nil, one payload field per non-Nil
      #     member.
      class Repr
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.types.unions.each do |union|
            table.reprs[union] = build(union, facts)
          end
        end

        private def build(union : IR::Type, facts : Analysis::Facts::Table) : Plans::Repr
          non_nil = union.members.reject(&.nil_type?)
          if union.nilable? && non_nil.size == 1 && pointer_repr?(non_nil.first, facts)
            Plans::PointerRepr.new(non_nil.first)
          else
            carrier(union)
          end
        end

        private def pointer_repr?(member : IR::Type, facts : Analysis::Facts::Table) : Bool
          return false unless member.reference?

          return true if facts.external_types[member]?.try(&.pointer?)
          return true unless member.family.class?

          (facts.struct_layouts[member.to_s]? || facts.struct_layouts[member.name]?).try(&.reference) != false
        end

        # Nil claims tag 0 first — the tag order lives here, never inherited
        # from member/display order — then non-Nil members take 1.. in a stable
        # order.
        private def carrier(union : IR::Type) : Plans::CarrierRepr
          variants = [] of Plans::CarrierRepr::Variant
          variants << Plans::CarrierRepr::Variant.new("Nil", 0, nil) if union.members.any?(&.nil_type?)

          union.members.reject(&.nil_type?).each do |member|
            variants << Plans::CarrierRepr::Variant.new(Mangle.sanitize(member.to_s), variants.size, member)
          end

          Plans::CarrierRepr.new(carrier_name(union), variants)
        end

        # The carrier name is minted from the union's canonical `to_s` through the
        # injective mangler, so distinct unions never collide on a name.
        private def carrier_name(union : IR::Type) : String
          "tangoU_#{Mangle.sanitize(union.to_s)}"
        end
      end
    end
  end
end
