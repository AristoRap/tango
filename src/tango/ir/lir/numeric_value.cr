module Tango
  module IR
    module LIR
      enum FloatIntrinsicOperation
        Negate
        Abs
        SignBit
        Ceil
        Floor
        Trunc
        RoundEven
        RoundAway
        Next
        Previous
      end

      # One unary Float64 operation whose exact IEEE behavior is committed
      # before the target boundary. The result type may be Float64 or Int32.
      class FloatIntrinsic < Value
        getter operation : FloatIntrinsicOperation
        getter value : Value
        getter type : IR::Type

        def initialize(@operation : FloatIntrinsicOperation, @value : Value, @type : IR::Type)
        end
      end

      # Crystal's checked Float64-to-integer conversion. This is distinct from
      # integer wrapping conversions and from target-native widening casts.
      class FloatToIntegerConvert < NumericConvert
        def initialize(value : Value, source : IR::Type, target : IR::Type)
          super(value, source, target)
        end
      end

      # Checked unary negation for Tango's signed integer widths.
      class IntegerNegate < Value
        getter value : Value
        getter type : IR::Type

        def initialize(@value : Value, @type : IR::Type)
        end
      end
    end
  end
end
