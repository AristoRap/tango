module Tango
  module Planning
    module Strategies
      # Maps analysis-proven union subset flows onto already-chosen carrier
      # representations. Only planning assigns conversion names and per-variant
      # tag/payload mappings.
      class UnionConversions
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(facts, table)
        end

        def run(facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.union_flows.each do |id, flow|
            source = table.reprs[flow.source]?.as?(Plans::CarrierRepr)
            target = table.reprs[flow.target]?.as?(Plans::CarrierRepr)
            next unless source && target

            variants = source.variants.compact_map do |source_variant|
              member = source_variant.payload || IR::Type::NIL
              target_variant = target.variants.find do |candidate|
                (candidate.payload || IR::Type::NIL) == member
              end
              next unless target_variant

              IR::CarrierConversionMap::Variant.new(
                member,
                source_variant.tag,
                target_variant.tag,
                source_variant.payload ? source_variant.label : nil,
                target_variant.payload ? target_variant.label : nil
              )
            end
            next unless variants.size == source.variants.size

            mapping = IR::CarrierConversionMap.new(
              conversion_name(flow.source, flow.target),
              source.name,
              target.name,
              variants
            )
            table.carrier_conversions[id] = Plans::CarrierConversion.new(flow.source, flow.target, mapping)
          end
        end

        private def conversion_name(source : IR::Type, target : IR::Type) : String
          "tangoWiden_#{Mangle.sanitize(source.to_s)}_to_#{Mangle.sanitize(target.to_s)}"
        end
      end
    end
  end
end
