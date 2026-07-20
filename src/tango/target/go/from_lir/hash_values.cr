module Tango
  module Target
    module Go
      class FromLIR
        # Hash operations share one representation gate. The concrete helper
        # spelling below is legal only because LIR carries an insertion-ordered
        # HashType selected by planning; the target does not infer that policy
        # from the source type or silently fall back to a native Go map.
        private def translate_hash_value(value : Tango::IR::LIR::HashValue, requirements : Array(Runtime::Requirement)) : IR::Expr
          @types.require_ordered_reference_hash(value.hash_type)

          case value
          when Tango::IR::LIR::HashNew
            requirements << Runtime::Helper.new("tangoHashNew")
            IR::Call.new(generic_hash_helper("tangoHashNew", value), [] of IR::Expr)
          when Tango::IR::LIR::HashGet
            requirements << Runtime::Helper.new("tangoHashGet")
            IR::Call.new(IR::Ident.new("tangoHashGet"), [translate_value(value.hash, requirements), translate_value(value.key, requirements)] of IR::Expr)
          when Tango::IR::LIR::HashSet
            requirements << Runtime::Helper.new("tangoHashSet")
            IR::Call.new(IR::Ident.new("tangoHashSet"), [translate_value(value.hash, requirements), translate_value(value.key, requirements), translate_value(value.value, requirements)] of IR::Expr)
          when Tango::IR::LIR::HashFetch
            requirements << Runtime::Helper.new("tangoHashFetch")
            IR::Call.new(IR::Ident.new("tangoHashFetch"), [translate_value(value.hash, requirements), translate_value(value.key, requirements), translate_value(value.default, requirements)] of IR::Expr)
          when Tango::IR::LIR::HashHasKey
            requirements << Runtime::Helper.new("tangoHashHas")
            IR::Call.new(IR::Ident.new("tangoHashHas"), [translate_value(value.hash, requirements), translate_value(value.key, requirements)] of IR::Expr)
          when Tango::IR::LIR::HashKeyAt
            IR::Index.new(IR::Selector.new(translate_value(value.hash, requirements), "keys"), translate_value(value.index, requirements))
          else
            raise "unsupported LIR hash value: #{value.class.name}"
          end
        end

        private def generic_hash_helper(name : String, value : Tango::IR::LIR::HashValue) : IR::GenericInst
          IR::GenericInst.new(IR::Ident.new(name), [go_type(value.key_type), go_type(value.value_type)])
        end
      end
    end
  end
end
