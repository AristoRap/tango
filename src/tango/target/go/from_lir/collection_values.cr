module Tango
  module Target
    module Go
      class FromLIR
        private def translate_collection_count(value : Tango::IR::LIR::CollectionCount, requirements : Array(Runtime::Requirement)) : IR::Expr
          length = case source = value.source
                   when Tango::IR::LIR::ArrayElements
                     IR::Call.new(IR::Ident.new("len"), [array_operand(source.value, source.element, requirements)] of IR::Expr)
                   when Tango::IR::LIR::HashEntries
                     keys = IR::Selector.new(translate_value(source.value, requirements), "keys")
                     IR::Call.new(IR::Ident.new("len"), [keys.as(IR::Expr)] of IR::Expr)
                   when Tango::IR::LIR::StringCodepoints
                     requirements << Runtime::Helper.new("tangoStringSize")
                     return IR::Call.new(IR::Ident.new("tangoStringSize"), [translate_value(source.value, requirements)] of IR::Expr)
                   else
                     raise ArgumentError.new("unsupported collection source: #{source.class.name}")
                   end

          IR::Call.new(IR::Ident.new("int32"), [length.as(IR::Expr)] of IR::Expr)
        end
      end
    end
  end
end
