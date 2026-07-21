module Tango
  module IR
    module NIR
      class TargetAnnotation
        getter path : Array(String)
        getter string_args : Array(String)
        getter symbol_args : Array(String)

        def initialize(@path : Array(String), @string_args : Array(String), @symbol_args : Array(String))
        end
      end

      class CallTarget
        getter name : String
        getter owner : String?
        getter owner_path : Array(String)
        getter annotations : Array(TargetAnnotation)

        def initialize(@name : String, @owner : String?, @annotations : Array(TargetAnnotation), @owner_path : Array(String) = [] of String)
        end
      end

      record Primitive, kind : Kind, name : String do
        enum Kind
          Binary
          CheckedAdd
          CheckedSub
          CheckedMul
          CheckedNegate
          FloatAdd
          FloatSub
          FloatMul
          FloatDiv
          FloatPower
          FloatIntrinsic
          FloorDiv
          FloorMod
          NumericConvert
          CheckedIntegerConvert
          CheckedFloatConvert
          WrappingIntegerConvert
          WrappingArithmetic
          Bitwise
          BitwiseNot
          IntegerShift
          IntegerPower
          CharOrd
          StringCompare
          ReferenceIdentity

          def self.from_annotation(symbol : String?) : Kind?
            case symbol
            when "binary"                   then Binary
            when "checked_add"              then CheckedAdd
            when "checked_sub"              then CheckedSub
            when "checked_mul"              then CheckedMul
            when "checked_negate"           then CheckedNegate
            when "float_add"                then FloatAdd
            when "float_sub"                then FloatSub
            when "float_mul"                then FloatMul
            when "float_div"                then FloatDiv
            when "float_power"              then FloatPower
            when "float_intrinsic"          then FloatIntrinsic
            when "floor_div"                then FloorDiv
            when "floor_mod"                then FloorMod
            when "numeric_convert"          then NumericConvert
            when "checked_integer_convert"  then CheckedIntegerConvert
            when "checked_float_convert"    then CheckedFloatConvert
            when "wrapping_integer_convert" then WrappingIntegerConvert
            when "wrapping_arithmetic"      then WrappingArithmetic
            when "bitwise"                  then Bitwise
            when "bitwise_not"              then BitwiseNot
            when "integer_shift"            then IntegerShift
            when "integer_power"            then IntegerPower
            when "char_ord"                 then CharOrd
            when "string_compare"           then StringCompare
            when "reference_identity"       then ReferenceIdentity
            end
          end

          # Primitive calls retain their receiver as operand zero in NIR.
          # Keeping arity on the shared kind prevents every frontend/lowering
          # consumer from rebuilding the unary-versus-binary family split.
          def operand_count : Int32
            case self
            in .numeric_convert?, .checked_integer_convert?,
               .checked_float_convert?, .wrapping_integer_convert?,
               .bitwise_not?, .char_ord?, .float_intrinsic?,
               .checked_negate? then 1
            in .binary?, .checked_add?, .checked_sub?, .checked_mul?,
               .wrapping_arithmetic?, .bitwise?, .integer_shift?,
               .integer_power?,
               .float_add?, .float_sub?, .float_mul?, .float_div?,
               .float_power?,
               .floor_div?, .floor_mod?, .string_compare?,
               .reference_identity? then 2
            end
          end
        end
      end

      alias ProcSignature = IR::ProcSignature

      class BlockArg < Stmt
        getter name : String
        getter name_span : Source::Range?

        def initialize(id : NodeId, @name : String, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, span)
        end
      end

      class BlockLiteral < Expr
        getter args : Array(BlockArg)
        getter body : Block
        getter signature : ProcSignature

        def initialize(id : NodeId, @args : Array(BlockArg), @body : Block, @signature : ProcSignature, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      # A `&block : A -> R` parameter on a def. Distinct from Param because it
      # carries a proc signature rather than a single type name.
      class BlockParam < Stmt
        getter name : String
        getter signature : ProcSignature
        getter? yield_parameter : Bool
        getter? value_required : Bool
        getter name_span : Source::Range?

        def initialize(id : NodeId, @name : String, @signature : ProcSignature, span : Source::Range?, @name_span : Source::Range? = nil, @yield_parameter : Bool = false, @value_required : Bool = false)
          super(id, span)
        end
      end

      # Invoking a proc value: `receiver.call(args)`. The receiver stays a real
      # expression so tooling resolves it to its declaration.
      class InvokeBlock < Expr
        getter receiver : Expr
        getter args : Array(Expr)
        getter? yield_site : Bool

        def initialize(id : NodeId, @receiver : Expr, @args : Array(Expr), type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil, @yield_site : Bool = false)
          super(id, type, span, method_site)
        end
      end

      # Receiverless positional call, optionally with an inline block.
      class Call < Expr
        getter name : String
        getter args : Array(Expr)
        getter targets : Array(CallTarget)
        getter block : BlockLiteral?
        getter primitive : Primitive?
        getter dispatch_receiver : ClassRef?
        # Range of the callee identifier itself (not the whole call), so
        # goto-definition resolves from anywhere on the name. Nil when the
        # frontend has no name location (e.g. synthesized calls).
        getter name_span : Source::Range?

        def initialize(id : NodeId, @name : String, @args : Array(Expr), @targets : Array(CallTarget), @block : BlockLiteral?, type : IR::Type?, span : Source::Range?, @primitive : Primitive? = nil, @name_span : Source::Range? = nil, method_site : MethodSite? = nil, @dispatch_receiver : ClassRef? = nil)
          super(id, type, span, method_site)
        end
      end
    end
  end
end
