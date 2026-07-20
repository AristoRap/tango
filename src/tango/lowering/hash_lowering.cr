module Tango
  module Lowering
    # Hash operation lowering, mixed into ToLIR. `ensure_hash` proves both a
    # planned representation and a native-equality key before any op lowers,
    # otherwise defers loudly with the comparability verdict's reason.
    module HashLowering
      private def ensure_hash(node : IR::NIR::HashExpr, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::UnsupportedValue?
        return nil if plans.hashes.has_key?(node.hash_type)
        verdict = facts.comparabilities[node.key_type]?
        reason = case verdict
                 when Analysis::Facts::GoRejects, Analysis::Facts::WrongSemantics
                   verdict.reason
                 else
                   "no native equality mapping"
                 end
        IR::LIR::UnsupportedValue.new("hash key #{node.key_type} cannot use native equality — #{reason}", loc(node.span))
      end

      private def lower_hash_new(node : IR::NIR::HashNew, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        ensure_hash(node, facts, plans) || IR::LIR::HashNew.new(node.hash_type)
      end

      private def lower_hash_get(node : IR::NIR::HashGet, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        ensure_hash(node, facts, plans) || IR::LIR::HashGet.new(lower_value(node.hash, facts, plans), lower_operand(node.key, node.key_type, facts, plans), node.hash_type)
      end

      private def lower_hash_set(node : IR::NIR::HashSet, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        ensure_hash(node, facts, plans) || IR::LIR::HashSet.new(lower_value(node.hash, facts, plans), lower_operand(node.key, node.key_type, facts, plans), lower_operand(node.value, node.value_type, facts, plans), node.hash_type)
      end

      private def lower_hash_fetch(node : IR::NIR::HashFetch, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        ensure_hash(node, facts, plans) || IR::LIR::HashFetch.new(lower_value(node.hash, facts, plans), lower_operand(node.key, node.key_type, facts, plans), lower_operand(node.default, node.value_type, facts, plans), node.hash_type)
      end

      private def lower_hash_has_key(node : IR::NIR::HashHasKey, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        ensure_hash(node, facts, plans) || IR::LIR::HashHasKey.new(lower_value(node.hash, facts, plans), lower_operand(node.key, node.key_type, facts, plans), node.hash_type)
      end

      private def lower_hash_key_at(node : IR::NIR::HashKeyAt, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        ensure_hash(node, facts, plans) || IR::LIR::HashKeyAt.new(lower_value(node.hash, facts, plans), lower_value(node.index, facts, plans), node.hash_type)
      end
    end
  end
end
