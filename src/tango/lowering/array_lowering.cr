module Tango
  module Lowering
    # Array operation lowering, mixed into ToLIR. Each op first proves the array
    # representation was planned (`ensure_array`) and otherwise defers loudly.
    module ArrayLowering
      private def ensure_array(type : IR::Type, plans : Planning::Plans::Table, source_loc : IR::LIR::SourceLoc?) : IR::LIR::UnsupportedValue?
        return nil if plans.arrays.has_key?(type)
        IR::LIR::UnsupportedValue.new("unplanned array #{type}", source_loc)
      end

      private def lower_array_new(node : IR::NIR::ArrayNew, plans : Planning::Plans::Table) : IR::LIR::Value
        type = IR::Type.array(node.element)
        ensure_array(type, plans, loc(node.span)) || IR::LIR::ArrayNew.new(type, node.element)
      end

      private def lower_array_build(node : IR::NIR::ArrayBuild, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        type = IR::Type.array(node.element)
        ensure_array(type, plans, loc(node.span)) || IR::LIR::ArrayBuild.new(type, node.element, lower_value(node.size, facts, plans))
      end

      private def lower_array_get(node : IR::NIR::ArrayGet, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        type = IR::Type.array(node.element)
        ensure_array(type, plans, loc(node.span)) || IR::LIR::ArrayGet.new(lower_value(node.array, facts, plans), lower_value(node.index, facts, plans), node.element)
      end

      private def lower_array_set(node : IR::NIR::ArraySet, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        type = IR::Type.array(node.element)
        ensure_array(type, plans, loc(node.span)) || IR::LIR::ArraySet.new(
          lower_value(node.array, facts, plans),
          lower_value(node.index, facts, plans),
          lower_operand(node.value, node.element, facts, plans),
          node.element
        )
      end

      private def lower_array_push(node : IR::NIR::ArrayPush, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        type = IR::Type.array(node.element)
        ensure_array(type, plans, loc(node.span)) || IR::LIR::ArrayPush.new(lower_value(node.array, facts, plans), lower_operand(node.value, node.element, facts, plans), node.element)
      end

      private def lower_string_split(node : IR::NIR::StringSplit, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        production = plans.collection_productions[node.id]?
        return IR::LIR::UnsupportedValue.new("unplanned collection production", loc(node.span)) unless production

        case production
        when Planning::Plans::MaterializedCollection
          separator = node.separator.try { |value| lower_value(value, facts, plans) }
          ensure_array(production.type, plans, loc(node.span)) || IR::LIR::MaterializedStringSplit.new(lower_value(node.string, facts, plans), production.type, separator)
        else
          IR::LIR::UnsupportedValue.new("unsupported collection production #{production.class.name}", loc(node.span))
        end
      end
    end
  end
end
