module Tango
  module Target
    module Go
      class FromLIR
        # Helper names are target-local. LIR carries only String operations
        # and the planned closure shape; the helpers provide code-point counting,
        # indexing, and range iteration without exposing Go to earlier phases.
        private def translate_string_value(value : Tango::IR::LIR::StringCharAt | Tango::IR::LIR::StringToFloat | Tango::IR::LIR::StringToInteger, requirements : Array(Runtime::Requirement)) : IR::Expr
          case value
          when Tango::IR::LIR::StringCharAt
            requirements << Runtime::Helper.new("tangoStringCharAt")
            IR::Call.new(IR::Ident.new("tangoStringCharAt"), [
              translate_value(value.string, requirements),
              translate_value(value.index, requirements),
            ] of IR::Expr)
          when Tango::IR::LIR::StringToFloat
            requirements << Runtime::Helper.new("tangoStringToF64")
            IR::Call.new(IR::Ident.new("tangoStringToF64"), [translate_value(value.string, requirements)] of IR::Expr)
          when Tango::IR::LIR::StringToInteger
            helper = "tangoStringTo#{integer_suffix(value.type)}"
            requirements << Runtime::Helper.new(helper)
            args = [translate_value(value.string, requirements)] of IR::Expr
            value.options.each { |option| args << translate_value(option, requirements) }
            IR::Call.new(IR::Ident.new(helper), args)
          else
            raise ArgumentError.new("unsupported LIR string value: #{value.class.name}")
          end
        end

        private def translate_string_each_char(stmt : Tango::IR::LIR::StringEachChar, requirements : Array(Runtime::Requirement)) : IR::ExprStmt
          helper = stmt.block.return_type == Tango::IR::Type.bool ? "tangoStringEachCharBreak" : "tangoStringEachChar"
          requirements << Runtime::Helper.new(helper)
          IR::ExprStmt.new(IR::Call.new(IR::Ident.new(helper), [
            translate_value(stmt.string, requirements),
            translate_value(stmt.block, requirements),
          ] of IR::Expr))
        end
      end
    end
  end
end
