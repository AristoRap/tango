module Tango
  module Lowering
    # Fixed code-point semantics need no representation strategy: Crystal
    # has typed the receiver/index/block, and lowering commits exactly those
    # language operations into LIR for the target to spell.
    module StringLowering
      private def lower_string_char_at(node : IR::NIR::StringCharAt, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::StringCharAt
        IR::LIR::StringCharAt.new(
          lower_value(node.string, facts, plans),
          lower_value(node.index, facts, plans)
        )
      end

      private def lower_string_to_float(node : IR::NIR::StringToFloat, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::StringToFloat
        IR::LIR::StringToFloat.new(lower_value(node.string, facts, plans))
      end

      private def lower_string_to_integer(node : IR::NIR::StringToInteger, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        type = node.type
        return IR::LIR::UnsupportedValue.new("string integer parse has no resolved integer type", loc(node.span)) unless type && type.family.int?

        IR::LIR::StringToInteger.new(
          lower_value(node.string, facts, plans),
          node.options.map { |option| lower_value(option, facts, plans) },
          type
        )
      end

      private def lower_string_each_char(node : IR::NIR::StringEachChar, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::StringEachChar
        block = lower_block_literal(node.block, facts, plans).as(IR::LIR::Closure)
        IR::LIR::StringEachChar.new(lower_value(node.string, facts, plans), block, loc(node.span))
      end

      # Calls conventionally remain expressions in NIR. Preserve a Nil result
      # when `each_char` appears in value position without bypassing its loop.
      private def lower_string_each_char_value(node : IR::NIR::StringEachChar, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::ValueSequence
        operation = lower_string_each_char(node, facts, plans)
        IR::LIR::ValueSequence.new([operation] of IR::LIR::Stmt, IR::LIR::NilValue.new, IR::Type::NIL)
      end
    end
  end
end
