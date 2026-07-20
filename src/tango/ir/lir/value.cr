module Tango
  module IR
    module LIR
      class ExternalTarget
        getter language : String
        getter package_name : String?
        getter name : String
        getter? receiver_method : Bool

        def initialize(@language : String, @package_name : String?, @name : String, @receiver_method : Bool = false)
        end
      end

      alias ProcSignature = IR::ProcSignature
      record SourceLoc, file : String, line : Int32, column : Int32

      abstract class Value
      end

      # A numeric literal committed with its structured type. The target spells
      # the explicit width conversion (`int32(5)`, `float64(1.5)`) from `type`;
      # the subclass is the literal-kind dispatch.
      abstract class NumericConst < Value
        getter value : String
        getter type : IR::Type

        def initialize(@value : String, @type : IR::Type)
        end
      end

      class IntConst < NumericConst
        def initialize(value : String, type : IR::Type = IR::Type.int(IR::Type::Width::I32))
          super(value, type)
        end
      end

      class FloatConst < NumericConst
        def initialize(value : String, type : IR::Type = IR::Type.float64)
          super(value, type)
        end
      end

      class StringConst < Value
        getter value : String

        def initialize(@value : String)
        end
      end

      class EnumConst < Value
        getter enum_type : IR::Type
        getter member : String

        def initialize(@enum_type : IR::Type, @member : String)
        end
      end

      class StringCharAt < Value
        getter string : Value
        getter index : Value

        def initialize(@string : Value, @index : Value)
        end
      end

      # The committed decimal parse operation. Its failure remains a typed
      # ArgumentError rather than a target-native zero value or raw error.
      class StringToFloat < Value
        getter string : Value

        def initialize(@string : Value)
        end
      end

      class StringToInteger < Value
        getter string : Value
        getter options : Array(Value)
        getter type : IR::Type

        def initialize(@string : Value, @options : Array(Value), @type : IR::Type)
        end
      end

      # One explicit conversion between resolved numeric types. The source and
      # target remain structured so targets only spell the committed cast.
      class NumericConvert < Value
        getter value : Value
        getter source : IR::Type
        getter target : IR::Type

        def initialize(@value : Value, @source : IR::Type, @target : IR::Type)
        end
      end

      enum IntegerConversionMode
        Checked
        Wrapping
      end

      # One conversion cell across the supported integer width matrix. Checked
      # conversions retain Crystal's OverflowError boundary; wrapping converts
      # modulo the target width.
      class IntegerConvert < NumericConvert
        getter mode : IntegerConversionMode

        def initialize(value : Value, source : IR::Type, target : IR::Type, @mode : IntegerConversionMode)
          super(value, source, target)
        end
      end

      # One scalar value committed to its language stringification boundary.
      # The source type stays structured for validation/dumps; presentation is
      # the language decision, so targets only spell it.
      class ScalarStringify < Value
        getter value : Value?
        getter effects : Array(Stmt)
        getter source : IR::Type
        getter presentation : IR::ScalarPresentation

        def initialize(@value : Value?, @effects : Array(Stmt), @source : IR::Type, @presentation : IR::ScalarPresentation)
        end
      end

      # Ordered, already-stringified interpolation pieces. Aggregation is a
      # separate value so targets never need to rediscover Crystal's call
      # plumbing or which arguments were literal segments versus holes.
      class Interpolation < Value
        getter pieces : Array(ScalarStringify)

        def initialize(@pieces : Array(ScalarStringify))
        end
      end

      class ExceptionValue < Value
        getter class_name : String
        getter message : Value?

        def initialize(@class_name : String, @message : Value?)
        end
      end

      class BoolConst < Value
        getter value : Bool

        def initialize(@value : Bool)
        end
      end

      class UnsupportedValue < Value
        getter reason : String
        getter loc : SourceLoc?

        def initialize(@reason : String, @loc : SourceLoc? = nil)
        end
      end

      # Go `nil` — the reference-nilable arm's null . A `*T` slot holds it
      # directly; Crystal `nil` IS Go `nil` there.
      class NilConst < Value
      end

      # The standalone `Nil` unit value — Crystal `nil` where the slot's type is
      # itself `Nil`, not a nilable union. Spelled as the zero-size `tangoNil{}`
      # literal, distinct from `NilConst`'s Go `nil` and a carrier's zero box.
      class NilValue < Value
      end

      # Shared state for operations over a value represented by a union
      # carrier. The value type remains explicit: Box admits the absent payload
      # of a Nil variant, while reads/checks require a concrete input value.
      abstract class CarrierValue(V) < Value
        getter value : V
        getter union : IR::Type

        def initialize(@value : V, @union : IR::Type)
        end
      end

      # A value crossing into a tagged carrier slot. Carries the target union
      # and which member is active as structured `Type`s (never a carrier name —
      # that policy lives in the `UnionType` declaration the target resolves). A
      # `nil` member is the carrier's tag-0 zero value, so `value` is absent.
      # Emitted as a FRESH composite literal so inactive payloads stay zero and
      # Go `==` is correct.
      class Box < CarrierValue(Value?)
        getter member : IR::Type?

        def initialize(value : Value?, union : IR::Type, @member : IR::Type?)
          super(value, union)
        end
      end

      # Reads the active payload of a carrier narrowed to a single member — the
      # inverse of Box. The pointer-nilable arm needs no Unbox (the pointer is
      # the value); lowering emits the value directly there.
      class Unbox < CarrierValue(Value)
        getter member : IR::Type

        def initialize(value : Value, union : IR::Type, @member : IR::Type)
          super(value, union)
        end
      end

      # Truthiness of a nilable in boolean context: carrier -> `.tag != 0`,
      # pointer -> `!= nil`. The target picks the spelling from whether a
      # `UnionType` carrier decl exists for `union`.
      class NilCheck < CarrierValue(Value)
      end

      # A carrier value crossing into a strict super-union carrier. `union` is
      # the target type inherited from CarrierValue; the named declaration owns
      # the complete per-variant retag/payload mapping.
      class Widen < CarrierValue(Value)
        getter source : IR::Type
        getter conversion : String

        def initialize(value : Value, @source : IR::Type, target : IR::Type, @conversion : String)
          super(value, target)
        end
      end

      class Temp < Value
        getter name : String

        def initialize(@name : String)
        end
      end

      abstract class BinaryValue < Value
        getter left : Value
        getter right : Value

        def initialize(@left : Value, @right : Value)
        end
      end

      class Binary < BinaryValue
        getter operator : String

        def initialize(left : Value, @operator : String, right : Value)
          super(left, right)
        end
      end

      class StringCompare < BinaryValue
      end

      class Not < Value
        getter value : Value

        def initialize(@value : Value)
        end
      end

      enum TypeTestStrategy
        StaticTrue
        StaticFalse
        PointerNonNil
        PointerNil
        CarrierTag
        CarrierNil
      end

      enum CastStrategy
        Passthrough
        PointerChecked
        CarrierChecked
      end

      abstract class DispatchRelationValue(S) < Value
        getter value : Value
        getter source : IR::Type
        getter target : IR::Type
        getter strategy : S

        def initialize(@value : Value, @source : IR::Type, @target : IR::Type, @strategy : S)
        end
      end

      class TypeTest < DispatchRelationValue(TypeTestStrategy)
        alias Strategy = TypeTestStrategy

        def initialize(value : Value, source : IR::Type, target : IR::Type, strategy : Strategy)
          super(value, source, target, strategy)
        end
      end

      class Cast < DispatchRelationValue(CastStrategy)
        alias Strategy = CastStrategy

        getter loc : SourceLoc?

        def initialize(value : Value, source : IR::Type, target : IR::Type, strategy : Strategy, @loc : SourceLoc? = nil)
          super(value, source, target, strategy)
        end
      end

      enum CheckedOperation
        Add
        Sub
        Mul
      end

      enum IntegerOperation
        WrappingAdd
        WrappingSub
        WrappingMul
        Pow
        WrappingPow
        BitAnd
        BitOr
        BitXor
        ShiftLeft
        ShiftRight
      end

      class IntegerOperationValue < BinaryValue
        getter kind : IntegerOperation
        getter type : IR::Type

        def initialize(@kind : IntegerOperation, left : Value, right : Value, @type : IR::Type)
          super(left, right)
        end
      end

      class IntegerBitNot < Value
        getter operand : Value
        getter type : IR::Type

        def initialize(@operand : Value, @type : IR::Type)
        end
      end

      enum FloatOperation
        Add
        Sub
        Mul
        Div
        Pow
        PowInteger
      end

      # One Float64 operation behind a runtime func boundary: the helper
      # call converts would-be Go constants into runtime values, preserving
      # Crystal's IEEE Infinity/NaN semantics. No strategy axis — Float64 has
      # exactly one representation, so the operation is the whole decision.
      class FloatArithmetic < BinaryValue
        getter operation : FloatOperation

        def initialize(@operation : FloatOperation, left : Value, right : Value)
          super(left, right)
        end
      end

      enum FloorOperation
        Div
        Mod
      end

      class FloorArithmetic < BinaryValue
        getter operation : FloorOperation
        getter type : IR::Type

        def initialize(@operation : FloorOperation, left : Value, right : Value, @type : IR::Type)
          super(left, right)
        end
      end

      # One width-carrying checked integer operation. Width and signedness live
      # in `type`; `operation` is the only remaining axis. Runtime strategy is
      # selected from those facts rather than encoded as one class per cell.
      class CheckedArithmetic < BinaryValue
        getter operation : CheckedOperation
        getter type : IR::Type
        getter strategy : IR::CheckedArithmeticStrategy

        def initialize(@operation : CheckedOperation, left : Value, right : Value, @type : IR::Type, @strategy : IR::CheckedArithmeticStrategy)
          super(left, right)
        end
      end

      class IfValue < Value
        getter cond : Value
        getter then_value : Value
        getter else_value : Value
        getter type : IR::Type?

        def initialize(@cond : Value, @then_value : Value, @else_value : Value, @type : IR::Type?)
        end
      end

      # A value-position begin/rescue. Each arm carries the statements that
      # precede its terminal value; an absent value means the arm exits
      # abruptly instead of filling the result slot. The handler strategy is
      # already fixed by planning, so this node is the lowering commitment the
      # target can spell as one typed slot plus the shared handler protocol.
      class RescueValue < Value
        class Arm
          getter body : Array(Stmt)
          getter value : Value?

          def initialize(@body : Array(Stmt), @value : Value?)
          end
        end

        getter body : Arm
        getter clauses : Array(RescueClause(Arm))
        getter else_arm : Arm?
        getter ensure_body : Array(Stmt)?
        getter type : IR::Type

        def initialize(@body : Arm, @clauses : Array(RescueClause(Arm)), @else_arm : Arm?, @ensure_body : Array(Stmt)?, @type : IR::Type)
        end
      end

      class Call < Value
        getter name : String
        getter args : Array(Value)

        def initialize(@name : String, @args : Array(Value))
        end
      end

      class ExternalCallValue < Value
        getter target : ExternalTarget
        getter args : Array(Value)

        def initialize(@target : ExternalTarget, @args : Array(Value))
        end
      end

      class FieldAccess < Value
        getter receiver : Value
        getter field : String

        def initialize(@receiver : Value, @field : String)
        end
      end

      class Alloc < Value
        getter type : IR::Type

        def initialize(@type : IR::Type)
        end

        def initialize(type_name : String)
          @type = IR::Type.klass(type_name)
        end

        def type_name : String
          type.to_s
        end
      end

      # The address of an existing value slot. Used when a value-struct
      # initializer mutates its constructor-local receiver before the value is
      # returned; reference classes already carry pointers and need no wrapper.
      class AddressOf < Value
        getter value : Value

        def initialize(@value : Value)
        end
      end

      class Closure < Value
        getter params : Array(Param)
        getter return_type : IR::Type?
        getter body : Array(Stmt)

        def initialize(@params : Array(Param), @return_type : IR::Type?, @body : Array(Stmt))
        end
      end

      class InvokeClosure < Value
        getter callee : Value
        getter args : Array(Value)

        def initialize(@callee : Value, @args : Array(Value))
        end
      end

      # `make(chan T)` / `make(chan T, capacity)`. Carries the element as a
      # structured `Type` so the target spells the `chan T` — no name re-parse.
      class MakeChan < Value
        getter element : IR::Type
        getter capacity : Value?

        def initialize(@element : IR::Type, @capacity : Value?)
        end
      end

      # `Mutex.new` — allocates the target's native mutex value. No structural
      # payload; `type` resolves through the source-declared external type
      # binding carried by the LIR program.
      class MakeMutex < Value
        getter type : IR::Type

        def initialize(@type : IR::Type)
        end
      end

      class ArrayNew < Value
        getter type : IR::Type
        getter element : IR::Type

        def initialize(@type : IR::Type, @element : IR::Type)
        end
      end

      class ArrayBuild < Value
        getter type : IR::Type
        getter element : IR::Type
        getter size : Value

        def initialize(@type : IR::Type, @element : IR::Type, @size : Value)
        end
      end

      # Shared receiver and element-type state for operations on an existing
      # Array(T). Its planned representation remains owned by Program#arrays.
      abstract class ArrayOperation < Value
        getter array : Value
        getter element : IR::Type

        def initialize(@array : Value, @element : IR::Type)
        end
      end

      class ArrayGet < ArrayOperation
        getter index : Value

        def initialize(array : Value, @index : Value, element : IR::Type)
          super(array, element)
        end
      end

      class ArraySet < ArrayOperation
        getter index : Value
        getter value : Value

        def initialize(array : Value, @index : Value, @value : Value, element : IR::Type)
          super(array, element)
        end
      end

      class ArrayPush < ArrayOperation
        getter value : Value

        def initialize(array : Value, @value : Value, element : IR::Type)
          super(array, element)
        end
      end

      # Whitespace or exact-separator splitting committed to Tango's
      # Array(String) result. The target consumes the planned array
      # representation rather than exposing its native collection through this
      # boundary.
      class MaterializedStringSplit < Value
        getter string : Value
        getter type : IR::Type
        getter separator : Value?

        def initialize(@string : Value, @type : IR::Type, @separator : Value? = nil)
        end

        def element : IR::Type
          type.element_type || IR::Type.unknown
        end
      end

      abstract class HashValue < Value
        getter hash_type : IR::Type

        def initialize(@hash_type : IR::Type)
        end

        def key_type : IR::Type
          hash_type.key_type || IR::Type.unknown
        end

        def value_type : IR::Type
          hash_type.value_type || IR::Type.unknown
        end
      end

      class HashNew < HashValue
        def initialize(hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashGet < HashValue
        getter hash : Value
        getter key : Value

        def initialize(@hash : Value, @key : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashSet < HashValue
        getter hash : Value
        getter key : Value
        getter value : Value

        def initialize(@hash : Value, @key : Value, @value : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashFetch < HashValue
        getter hash : Value
        getter key : Value
        getter default : Value

        def initialize(@hash : Value, @key : Value, @default : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashHasKey < HashValue
        getter hash : Value
        getter key : Value

        def initialize(@hash : Value, @key : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      class HashKeyAt < HashValue
        getter hash : Value
        getter index : Value

        def initialize(@hash : Value, @index : Value, hash_type : IR::Type)
          super(hash_type)
        end
      end

      # A planned logical source whose cardinality a terminal may consume.
      # Sources grow independently from terminals and later transforms.
      abstract class CollectionSource
        getter value : Value

        def initialize(@value : Value)
        end
      end

      class ArrayElements < CollectionSource
        getter element : IR::Type

        def initialize(value : Value, @element : IR::Type)
          super(value)
        end
      end

      class HashEntries < CollectionSource
        getter hash_type : IR::Type

        def initialize(value : Value, @hash_type : IR::Type)
          super(value)
        end
      end

      class StringCodepoints < CollectionSource
      end

      # Non-empty exact-separator segments traversed without constructing the
      # source-level Array(String). Planning proves the traversal is its only
      # direct consumer before lowering may create this source.
      class StringSegments < CollectionSource
        getter separator : Value

        def initialize(value : Value, @separator : Value)
          super(value)
        end
      end

      class CollectionCount < Value
        getter source : CollectionSource

        def initialize(@source : CollectionSource)
        end
      end

      # Independent transform and terminal axes for an already-selected
      # collection traversal. These are deliberately not Values: only the
      # composed traversal is a value in the surrounding program.
      abstract class CollectionTransform
        getter block : Closure

        def initialize(@block : Closure)
        end
      end

      class CollectionFilterTransform < CollectionTransform
      end

      class CollectionMapTransform < CollectionTransform
      end

      abstract class CollectionTerminal
        getter block : Closure

        def initialize(@block : Closure)
        end
      end

      class CollectionFoldTerminal < CollectionTerminal
        getter initial : Value
        getter type : IR::Type

        def initialize(@initial : Value, block : Closure, @type : IR::Type)
          super(block)
        end
      end

      class CollectionEachTerminal < CollectionTerminal
      end

      # The explicit lowering commitment for one fused traversal. The source,
      # ordered transforms, and terminal remain orthogonal so future sources or
      # transforms do not create per-combination node classes.
      class FusedCollectionTraversal < Value
        getter source : CollectionSource
        getter transforms : Array(CollectionTransform)
        getter terminal : CollectionTerminal
        getter type : IR::Type

        def initialize(@source : CollectionSource, @transforms : Array(CollectionTransform), @terminal : CollectionTerminal, @type : IR::Type)
        end
      end

      # A lowered value-producing sequence. The target spells this as an
      # immediately invoked typed closure; lowering has already fixed the
      # ordered prefix and result value.
      class ValueSequence < Value
        getter body : Array(Stmt)
        getter value : Value
        getter type : IR::Type

        def initialize(@body : Array(Stmt), @value : Value, @type : IR::Type)
        end
      end

      abstract class ChannelReceiveValue < Value
        getter channel : Value
        getter element : IR::Type

        def initialize(@channel : Value, @element : IR::Type)
        end
      end

      # A checked receive: reads a value, panicking on a closed channel (the
      # target routes it through the `tangoChanRecv` helper). `element` types the
      # helper instantiation.
      class ChanReceive < ChannelReceiveValue
        def initialize(channel : Value, element : IR::Type)
          super(channel, element)
        end
      end

      # A raw receive `<-ch` producing the element directly — the unchecked arm
      # behind `receive?`. For a reference element it IS the `T?` value,
      # so no carrier or comma-ok is needed. `element` types it.
      class ChanReceiveMaybe < ChannelReceiveValue
        def initialize(channel : Value, element : IR::Type)
          super(channel, element)
        end
      end

      # A value-element `receive?`: Go comma-ok receive followed by a carrier
      # box only when `ok` is true. The carrier's zero value is the nil variant,
      # so lowering commits the union and the target only spells the protocol.
      class ChanReceiveMaybeBox < ChannelReceiveValue
        getter union : IR::Type

        def initialize(channel : Value, element : IR::Type, @union : IR::Type)
          super(channel, element)
        end
      end

      # One closed-aware channel receive. The operational leaf preserves the
      # received value and Go's comma-ok state as a language-level value struct;
      # Channel#next decides how closure maps to Iterator::Stop in ordinary
      # Tango code.
      class ChanReceiveState < ChannelReceiveValue
        getter result_type : IR::Type
        getter value_field : String
        getter open_field : String

        def initialize(channel : Value, element : IR::Type, @result_type : IR::Type, @value_field : String, @open_field : String)
          super(channel, element)
        end
      end
    end
  end
end
