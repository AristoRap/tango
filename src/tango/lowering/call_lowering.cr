module Tango
  module Lowering
    # Commits resolved internal/external calls and numeric primitive calls to
    # LIR. Call policy is already present in Facts and Plans at this boundary.
    module CallLowering
      private def lower_call_value(stmt : IR::NIR::Call, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        case primitive = stmt.primitive
        when IR::NIR::Primitive
          lower_primitive_call(stmt, primitive, facts, plans)
        else
          case plan = plans.calls[stmt.id]?
          when Planning::Plans::ExternalGo
            args = stmt.args.map { |arg| lower_value(arg, facts, plans) }
            IR::LIR::ExternalCallValue.new(lower_external_target(plan.callee), args)
          when Planning::Plans::InternalCall
            lower_internal_call(stmt, plan, facts, plans)
          else
            IR::LIR::UnsupportedValue.new("unsupported value call #{stmt.name}", loc(stmt.span))
          end
        end
      end

      private def lower_internal_call(stmt : IR::NIR::Call, plan : Planning::Plans::InternalCall, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Call
        args = stmt.args.map { |arg| lower_value(arg, facts, plans) }
        stmt.block.try { |block| args << lower_value(block, facts, plans) }
        IR::LIR::Call.new(plan.name, args)
      end

      private def lower_external_target(callee : Analysis::Facts::GoExternal) : IR::LIR::ExternalTarget
        IR::LIR::ExternalTarget.new(
          callee.binding,
          callee.receiver_method?,
          dependency: callee.dependency
        )
      end

      private def normalize_operator(name : String) : String
        name == "===" ? "==" : name
      end

      private def lower_primitive_call(stmt : IR::NIR::Call, primitive : IR::NIR::Primitive, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        return IR::LIR::UnsupportedValue.new("unsupported primitive arity for #{stmt.name}", loc(stmt.span)) unless stmt.args.size == primitive.kind.operand_count

        if primitive.kind.numeric_convert?
          source = stmt.args.first.type
          target = stmt.type
          numeric = source && target && (source.family.int? || source.family.float?) && (target.family.int? || target.family.float?)
          return IR::LIR::UnsupportedValue.new("numeric conversion has no resolved numeric types", loc(stmt.span)) unless source && target && numeric

          return IR::LIR::NumericConvert.new(lower_value(stmt.args.first, facts, plans), source, target)
        end

        if primitive.kind.checked_integer_convert? || primitive.kind.wrapping_integer_convert?
          source = stmt.args.first.type
          target = stmt.type
          valid = source && target && source.family.int? && target.family.int?
          return IR::LIR::UnsupportedValue.new("integer conversion has no resolved integer types", loc(stmt.span)) unless source && target && valid

          mode = primitive.kind.checked_integer_convert? ? IR::LIR::IntegerConversionMode::Checked : IR::LIR::IntegerConversionMode::Wrapping
          return IR::LIR::IntegerConvert.new(lower_value(stmt.args.first, facts, plans), source, target, mode)
        end

        if primitive.kind.checked_float_convert?
          source = stmt.args.first.type
          target = stmt.type
          valid = source.try(&.family.float?) && target.try(&.family.int?)
          return IR::LIR::UnsupportedValue.new("float conversion has no resolved Float64 -> integer types", loc(stmt.span)) unless source && target && valid

          return IR::LIR::FloatToIntegerConvert.new(lower_value(stmt.args.first, facts, plans), source, target)
        end

        if primitive.kind.char_ord?
          source = stmt.args.first.type
          target = stmt.type
          valid = source.try(&.family.char?) && target.try(&.family.int?)
          return IR::LIR::UnsupportedValue.new("Char#ord has no resolved Char -> integer types", loc(stmt.span)) unless source && target && valid

          return IR::LIR::NumericConvert.new(lower_value(stmt.args.first, facts, plans), source, target)
        end

        if primitive.kind.bitwise_not?
          type = stmt.type
          return IR::LIR::UnsupportedValue.new("bitwise not has no resolved integer type", loc(stmt.span)) unless type && type.family.int?

          return IR::LIR::IntegerBitNot.new(lower_value(stmt.args.first, facts, plans), type)
        end

        if primitive.kind.checked_negate?
          type = stmt.type
          valid = type.try(&.family.int?) && type.try(&.width).try(&.signed?)
          return IR::LIR::UnsupportedValue.new("checked negate has no resolved signed integer type", loc(stmt.span)) unless type && valid

          return IR::LIR::IntegerNegate.new(lower_value(stmt.args.first, facts, plans), type)
        end

        if primitive.kind.float_intrinsic?
          type = stmt.type
          return IR::LIR::UnsupportedValue.new("float intrinsic has no resolved result type", loc(stmt.span)) unless type

          operation = float_intrinsic_operation(stmt.name)
          return IR::LIR::FloatIntrinsic.new(operation, lower_value(stmt.args.first, facts, plans), type)
        end

        left = lower_value(stmt.args[0], facts, plans)
        right = lower_value(stmt.args[1], facts, plans)

        case primitive.kind
        in .reference_identity?
          IR::LIR::Binary.new(left, "==", right)
        in .binary?
          if stmt.name.in?("==", "!=", "===") && !plans.equalities.has_key?(stmt.id)
            return IR::LIR::UnsupportedValue.new("#{stmt.args.first?.try(&.type) || "?"} cannot use native equality", loc(stmt.span))
          end
          IR::LIR::Binary.new(left, normalize_operator(primitive.name), right)
        in .checked_add?
          checked_type = stmt.type
          return IR::LIR::UnsupportedValue.new("checked add has no resolved integer type", loc(stmt.span)) unless checked_type && checked_type.family.int?
          checked_arithmetic(IR::LIR::CheckedOperation::Add, stmt, left, right, checked_type, plans)
        in .checked_sub?
          checked_type = stmt.type
          return IR::LIR::UnsupportedValue.new("checked subtract has no resolved integer type", loc(stmt.span)) unless checked_type && checked_type.family.int?
          checked_arithmetic(IR::LIR::CheckedOperation::Sub, stmt, left, right, checked_type, plans)
        in .checked_mul?
          checked_type = stmt.type
          return IR::LIR::UnsupportedValue.new("checked multiply has no resolved integer type", loc(stmt.span)) unless checked_type && checked_type.family.int?
          checked_arithmetic(IR::LIR::CheckedOperation::Mul, stmt, left, right, checked_type, plans)
        in .wrapping_arithmetic?
          integer_operation(wrapping_operation(stmt.name), stmt, left, right)
        in .bitwise?
          integer_operation(bitwise_operation(stmt.name), stmt, left, right)
        in .integer_shift?
          integer_operation(shift_operation(stmt.name), stmt, left, right)
        in .integer_power?
          integer_operation(power_operation(stmt.name), stmt, left, right)
        in .float_add?
          float_arithmetic(IR::LIR::FloatOperation::Add, stmt, left, right)
        in .float_sub?
          float_arithmetic(IR::LIR::FloatOperation::Sub, stmt, left, right)
        in .float_mul?
          float_arithmetic(IR::LIR::FloatOperation::Mul, stmt, left, right)
        in .float_div?
          float_arithmetic(IR::LIR::FloatOperation::Div, stmt, left, right)
        in .float_power?
          operation = stmt.args[1].type == IR::Type.int(IR::Type::Width::I32) ? IR::LIR::FloatOperation::PowInteger : IR::LIR::FloatOperation::Pow
          float_arithmetic(operation, stmt, left, right)
        in .floor_div?
          floor_arithmetic(IR::LIR::FloorOperation::Div, stmt, left, right)
        in .floor_mod?
          floor_arithmetic(IR::LIR::FloorOperation::Mod, stmt, left, right)
        in .string_compare?
          IR::LIR::StringCompare.new(left, right)
        in .numeric_convert?, .checked_integer_convert?, .checked_float_convert?,
           .wrapping_integer_convert?, .bitwise_not?, .char_ord?,
           .float_intrinsic?, .checked_negate?
          raise "unreachable primitive arity branch"
        end
      end

      private def integer_operation(operation : IR::LIR::IntegerOperation, stmt : IR::NIR::Call, left : IR::LIR::Value, right : IR::LIR::Value) : IR::LIR::Value
        type = stmt.type
        return IR::LIR::UnsupportedValue.new("integer operation has no resolved integer type", loc(stmt.span)) unless type && type.family.int?

        IR::LIR::IntegerOperationValue.new(operation, left, right, type)
      end

      private def wrapping_operation(name : String) : IR::LIR::IntegerOperation
        case name
        when "&+" then IR::LIR::IntegerOperation::WrappingAdd
        when "&-" then IR::LIR::IntegerOperation::WrappingSub
        when "&*" then IR::LIR::IntegerOperation::WrappingMul
        else           raise "unsupported wrapping integer operation #{name}"
        end
      end

      private def bitwise_operation(name : String) : IR::LIR::IntegerOperation
        case name
        when "&" then IR::LIR::IntegerOperation::BitAnd
        when "|" then IR::LIR::IntegerOperation::BitOr
        when "^" then IR::LIR::IntegerOperation::BitXor
        else          raise "unsupported bitwise integer operation #{name}"
        end
      end

      private def shift_operation(name : String) : IR::LIR::IntegerOperation
        case name
        when "<<" then IR::LIR::IntegerOperation::ShiftLeft
        when ">>" then IR::LIR::IntegerOperation::ShiftRight
        else           raise "unsupported integer shift #{name}"
        end
      end

      private def power_operation(name : String) : IR::LIR::IntegerOperation
        case name
        when "**"  then IR::LIR::IntegerOperation::Pow
        when "&**" then IR::LIR::IntegerOperation::WrappingPow
        else            raise "unsupported integer power #{name}"
        end
      end

      private def float_intrinsic_operation(name : String) : IR::LIR::FloatIntrinsicOperation
        case name
        when "-"                   then IR::LIR::FloatIntrinsicOperation::Negate
        when "abs"                 then IR::LIR::FloatIntrinsicOperation::Abs
        when "sign_bit"            then IR::LIR::FloatIntrinsicOperation::SignBit
        when "ceil"                then IR::LIR::FloatIntrinsicOperation::Ceil
        when "floor"               then IR::LIR::FloatIntrinsicOperation::Floor
        when "trunc"               then IR::LIR::FloatIntrinsicOperation::Trunc
        when "round", "round_even" then IR::LIR::FloatIntrinsicOperation::RoundEven
        when "round_away"          then IR::LIR::FloatIntrinsicOperation::RoundAway
        when "next_float"          then IR::LIR::FloatIntrinsicOperation::Next
        when "prev_float"          then IR::LIR::FloatIntrinsicOperation::Previous
        else                            raise "unsupported float intrinsic #{name}"
        end
      end

      private def float_arithmetic(operation : IR::LIR::FloatOperation, stmt : IR::NIR::Call, left : IR::LIR::Value, right : IR::LIR::Value) : IR::LIR::Value
        type = stmt.type
        return IR::LIR::UnsupportedValue.new("float arithmetic has no resolved float type", loc(stmt.span)) unless type && type.family.float?

        IR::LIR::FloatArithmetic.new(operation, left, right)
      end

      private def floor_arithmetic(operation : IR::LIR::FloorOperation, stmt : IR::NIR::Call, left : IR::LIR::Value, right : IR::LIR::Value) : IR::LIR::Value
        type = stmt.type
        numeric = type && (type.family.int? || type.family.float?)
        return IR::LIR::UnsupportedValue.new("floor arithmetic has no resolved numeric type", loc(stmt.span)) unless type && numeric

        IR::LIR::FloorArithmetic.new(operation, left, right, type)
      end

      private def checked_arithmetic(operation : IR::LIR::CheckedOperation, stmt : IR::NIR::Call, left : IR::LIR::Value, right : IR::LIR::Value, type : IR::Type, plans : Planning::Plans::Table) : IR::LIR::Value
        plan = plans.checked_arithmetic[stmt.id]?
        return IR::LIR::UnsupportedValue.new("checked arithmetic has no strategy", loc(stmt.span)) unless plan

        IR::LIR::CheckedArithmetic.new(operation, left, right, type, plan.strategy)
      end
    end
  end
end
