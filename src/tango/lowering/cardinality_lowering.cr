module Tango
  module Lowering
    module CardinalityLowering
      private def lower_size(node : IR::NIR::Size, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        plan = plans.cardinalities[node.id]?
        return IR::LIR::UnsupportedValue.new("unplanned cardinality", loc(node.span)) unless plan

        source = case plan
                 when Planning::Plans::StoredCardinality
                   value = lower_value(node.value, facts, plans)
                   case plan.source
                   in .array_elements?
                     element = plan.source_type.element_type || IR::Type.unknown
                     return ensure_array(plan.source_type, plans, loc(node.span)) || IR::LIR::CollectionCount.new(IR::LIR::ArrayElements.new(value, element))
                   in .hash_entries?
                     return IR::LIR::UnsupportedValue.new("unplanned hash #{plan.source_type}", loc(node.span)) unless plans.hashes.has_key?(plan.source_type)
                     IR::LIR::HashEntries.new(value, plan.source_type)
                   end
                 when Planning::Plans::CodepointCardinality
                   IR::LIR::StringCodepoints.new(lower_value(node.value, facts, plans))
                 else
                   return IR::LIR::UnsupportedValue.new("unsupported cardinality plan #{plan.class.name}", loc(node.span))
                 end
        IR::LIR::CollectionCount.new(source)
      end
    end
  end
end
