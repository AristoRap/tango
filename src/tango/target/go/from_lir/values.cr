module Tango
  module Target
    module Go
      class FromLIR
        # The single mechanical LIR-value dispatcher. Family-specific spelling
        # remains in focused collaborators; this file owns only value routing.
        private def translate_value(value : Tango::IR::LIR::Value, requirements : Array(Runtime::Requirement)) : IR::Expr
          case value
          when Tango::IR::LIR::IntConst
            IR::Call.new(IR::Ident.new(go_type(value.type)), [IR::IntLit.new(value.value)] of IR::Expr)
          when Tango::IR::LIR::FloatConst
            literal = IR::Call.new(IR::Ident.new(go_type(value.type)), [IR::FloatLit.new(value.value)] of IR::Expr)
            if value.value.starts_with?('-') && value.value.to_f64 == 0.0
              requirements << Runtime::Helper.new("tangoNegateF64")
              IR::Call.new(IR::Ident.new("tangoNegateF64"), [literal] of IR::Expr)
            else
              literal
            end
          when Tango::IR::LIR::StringConst
            IR::StringLit.new(value.value)
          when Tango::IR::LIR::EnumConst
            IR::Ident.new(@types.enum_member_name(value.enum_type, value.member))
          when Tango::IR::LIR::StringCharAt, Tango::IR::LIR::StringToFloat, Tango::IR::LIR::StringToInteger
            translate_string_value(value, requirements)
          when Tango::IR::LIR::CollectionCount
            translate_collection_count(value, requirements)
          when Tango::IR::LIR::FusedCollectionTraversal
            translate_fused_collection(value, requirements)
          when Tango::IR::LIR::ScalarStringify
            translate_scalar_stringify(value, requirements)
          when Tango::IR::LIR::Interpolation
            translated = value.pieces.map { |piece| translate_value(piece, requirements) }
            translated.reduce(IR::StringLit.new("").as(IR::Expr)) { |left, right| IR::Binary.new(left, "+", right) }
          when Tango::IR::LIR::ExceptionValue
            translate_exception_value(value, requirements)
          when Tango::IR::LIR::BoolConst
            IR::BoolLit.new(value.value)
          when Tango::IR::LIR::IfValue
            translate_if_value_expression(value, requirements)
          when Tango::IR::LIR::Temp
            IR::Ident.new(value.name)
          when Tango::IR::LIR::Binary
            IR::Binary.new(translate_value(value.left, requirements), value.operator, translate_value(value.right, requirements))
          when Tango::IR::LIR::IntegerConvert
            translated = translate_value(value.value, requirements)
            if value.mode.checked?
              helper = integer_conversion_helper(value.source, value.target)
              requirements << Runtime::Helper.new(helper)
              IR::Call.new(IR::Ident.new(helper), [translated] of IR::Expr)
            else
              helper = "tangoWrapping#{integer_conversion_helper(value.source, value.target).lchop("tango")}"
              requirements << Runtime::Helper.new(helper)
              IR::Call.new(IR::Ident.new(helper), [translated] of IR::Expr)
            end
          when Tango::IR::LIR::FloatToIntegerConvert
            helper = "tangoConvertF64To#{integer_suffix(value.target)}"
            requirements << Runtime::Helper.new(helper)
            IR::Call.new(IR::Ident.new(helper), [translate_value(value.value, requirements)] of IR::Expr)
          when Tango::IR::LIR::NumericConvert
            IR::Call.new(IR::Ident.new(go_type(value.target)), [translate_value(value.value, requirements)] of IR::Expr)
          when Tango::IR::LIR::StringCompare
            requirements << Runtime::Helper.new("tangoStringCompare")
            IR::Call.new(IR::Ident.new("tangoStringCompare"), [translate_value(value.left, requirements), translate_value(value.right, requirements)] of IR::Expr)
          when Tango::IR::LIR::FloatIntrinsic
            helper = "tango#{value.operation}F64"
            requirements << Runtime::Helper.new(helper)
            IR::Call.new(IR::Ident.new(helper), [translate_value(value.value, requirements)] of IR::Expr)
          when Tango::IR::LIR::Not
            IR::Not.new(translate_value(value.value, requirements))
          when Tango::IR::LIR::IntegerBitNot
            IR::BitNot.new(translate_value(value.operand, requirements))
          when Tango::IR::LIR::IntegerNegate
            helper = "tangoNegate#{integer_suffix(value.type)}"
            requirements << Runtime::Helper.new(helper)
            IR::Call.new(IR::Ident.new(helper), [translate_value(value.value, requirements)] of IR::Expr)
          when Tango::IR::LIR::IntegerOperationValue
            translate_integer_operation(value, requirements)
          when Tango::IR::LIR::TypeTest
            translate_type_test(value, requirements)
          when Tango::IR::LIR::Cast
            translate_cast(value, requirements)
          when Tango::IR::LIR::CheckedArithmetic
            helper = checked_arithmetic_helper(value.operation, value.type, value.strategy)
            requirements << Runtime::Helper.new(helper)
            IR::Call.new(IR::Ident.new(helper), [translate_value(value.left, requirements), translate_value(value.right, requirements)] of IR::Expr)
          when Tango::IR::LIR::FloatArithmetic
            helper = "tango#{value.operation}F64"
            requirements << Runtime::Helper.new(helper)
            IR::Call.new(IR::Ident.new(helper), [translate_value(value.left, requirements), translate_value(value.right, requirements)] of IR::Expr)
          when Tango::IR::LIR::FloorArithmetic
            helper = floor_arithmetic_helper(value.operation, value.type)
            requirements << Runtime::Helper.new(helper)
            IR::Call.new(IR::Ident.new(helper), [translate_value(value.left, requirements), translate_value(value.right, requirements)] of IR::Expr)
          when Tango::IR::LIR::FieldAccess
            IR::Selector.new(translate_value(value.receiver, requirements), value.field)
          when Tango::IR::LIR::Alloc
            literal = IR::CompositeLit.new(@types.struct_name(value.type))
            @types.value_struct?(value.type) ? literal : IR::AddrOf.new(literal)
          when Tango::IR::LIR::AddressOf
            IR::AddrOf.new(translate_value(value.value, requirements))
          when Tango::IR::LIR::Call
            IR::Call.new(IR::Ident.new(value.name), value.args.map { |arg| translate_value(arg, requirements) })
          when Tango::IR::LIR::ExternalCallValue
            external_call(value.target, value.args, requirements)
          when Tango::IR::LIR::InvokeClosure
            IR::Call.new(translate_value(value.callee, requirements), value.args.map { |arg| translate_value(arg, requirements) })
          when Tango::IR::LIR::Closure
            translate_closure(value, requirements)
          when Tango::IR::LIR::MakeChan
            IR::MakeChan.new(go_type(value.element), value.capacity.try { |capacity| translate_value(capacity, requirements) })
          when Tango::IR::LIR::MakeMutex
            IR::AddrOf.new(IR::CompositeLit.new(@types.external_literal_type(value.type)))
          when Tango::IR::LIR::ArrayNew
            requirements << Runtime::Helper.new("tangoArrayNew")
            IR::Call.new(generic_helper("tangoArrayNew", value.element), [] of IR::Expr)
          when Tango::IR::LIR::ArrayBuild
            requirements << Runtime::Helper.new("tangoArrayBuild")
            IR::Call.new(generic_helper("tangoArrayBuild", value.element), [translate_value(value.size, requirements)] of IR::Expr)
          when Tango::IR::LIR::ArrayGet
            IR::Index.new(array_operand(value.array, value.element, requirements), translate_value(value.index, requirements))
          when Tango::IR::LIR::ArraySet
            requirements << Runtime::Helper.new("tangoArraySet")
            IR::Call.new(IR::Ident.new("tangoArraySet"), [
              translate_value(value.array, requirements),
              translate_value(value.index, requirements),
              translate_value(value.value, requirements),
            ] of IR::Expr)
          when Tango::IR::LIR::ArrayPush
            requirements << Runtime::Helper.new("tangoArrayPush")
            IR::Call.new(IR::Ident.new("tangoArrayPush"), [translate_value(value.array, requirements), translate_value(value.value, requirements)] of IR::Expr)
          when Tango::IR::LIR::MaterializedStringSplit
            raise "unsupported split array representation #{value.type}" unless @types.array_reference?(value.element)
            if separator = value.separator
              requirements << Runtime::Helper.new("tangoStringSplitOn")
              IR::Call.new(IR::Ident.new("tangoStringSplitOn"), [translate_value(value.string, requirements), translate_value(separator, requirements)] of IR::Expr)
            else
              requirements << Runtime::Helper.new("tangoStringSplit")
              IR::Call.new(IR::Ident.new("tangoStringSplit"), [translate_value(value.string, requirements)] of IR::Expr)
            end
          when Tango::IR::LIR::HashValue
            translate_hash_value(value, requirements)
          when Tango::IR::LIR::ValueSequence
            body = translate_body(value.body, requirements)
            body << IR::ReturnStmt.new(translate_value(value.value, requirements))
            IR::Call.new(IR::FuncLit.new([] of IR::Param, go_type(value.type), body), [] of IR::Expr)
          when Tango::IR::LIR::ChanReceive
            requirements << Runtime::Helper.new("tangoChanRecv")
            IR::Call.new(IR::Ident.new("tangoChanRecv"), [translate_value(value.channel, requirements)] of IR::Expr)
          when Tango::IR::LIR::ChanReceiveMaybe
            IR::RecvExpr.new(translate_value(value.channel, requirements))
          when Tango::IR::LIR::ChanReceiveMaybeBox
            translate_receive_maybe_box(value, requirements)
          when Tango::IR::LIR::ChanReceiveState
            translate_receive_state(value, requirements)
          when Tango::IR::LIR::NilConst
            IR::Ident.new("nil")
          when Tango::IR::LIR::NilValue
            requirements << Runtime::Helper.new("tangoNil")
            IR::CompositeLit.new("tangoNil")
          when Tango::IR::LIR::Box
            translate_box(value, requirements)
          when Tango::IR::LIR::Unbox
            IR::Selector.new(translate_value(value.value, requirements), payload_field(value.union, value.member))
          when Tango::IR::LIR::NilCheck
            translate_nil_check(value, requirements)
          when Tango::IR::LIR::Widen
            IR::Call.new(IR::Ident.new(value.conversion), [translate_value(value.value, requirements)] of IR::Expr)
          when Tango::IR::LIR::UnsupportedValue
            IR::StringLit.new(value.reason)
          else
            IR::StringLit.new("unsupported LIR value")
          end
        end
      end
    end
  end
end
