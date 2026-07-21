module Tango
  module Planning
    module Plans
      abstract class CallPlan
      end

      enum BlockMode
        Plain
        Value
        Protocol

        # The mode of a yield block: Value when the yield must produce a value,
        # Protocol otherwise. The one mapping the def-site (Monomorphize) and the
        # call-site (Blocks) classifications share, so the two can't disagree on
        # what a value-yielding vs protocol-yielding block resolves to.
        def self.for_yield(value_required : Bool) : BlockMode
          value_required ? Value : Protocol
        end
      end

      class ExternalGo < CallPlan
        getter callee : Analysis::Facts::GoExternal

        def initialize(@callee : Analysis::Facts::GoExternal)
        end
      end

      class InternalCall < CallPlan
        getter name : String

        def initialize(@name : String)
        end
      end

      class UnsupportedCall < CallPlan
      end

      class CapabilityDispatch
        enum Strategy
          StaticSpecialization
        end

        getter concrete : IR::Type
        getter capability : IR::Type
        getter strategy : Strategy

        def initialize(@concrete : IR::Type, @capability : IR::Type, @strategy : Strategy)
        end
      end

      # The monomorphized function name a NIR::Def lowers to.
      class DefPlan
        getter name : String
        getter block_mode : BlockMode

        def initialize(@name : String, @block_mode : BlockMode = BlockMode::Plain)
        end
      end

      record NamespacePlan, path : Array(String), target_prefix : String
      record ConstantPlan, path : Array(String), target_name : String, type : IR::Type
      record TypeAliasPlan, path : Array(String), target : IR::Type

      # The chosen representation of a class: its ordered fields plus whether
      # it is a reference type (pointer) or a value type. The current surface only
      # produces reference classes; value structs wait for a struct example.
      class ClassLayout
        getter name : String
        getter fields : Array(IR::Field)
        getter reference : Bool
        getter exception_ancestors : Array(String)
        getter? identity_padding : Bool

        def initialize(@name : String, @fields : Array(IR::Field), @reference : Bool, @exception_ancestors : Array(String) = [] of String, @identity_padding : Bool = false)
        end

        def exception_runtime? : Bool
          !exception_ancestors.empty?
        end
      end

      # How a `.new` is committed: the function name to call, the initialize
      # function that name's body dispatches to, and the concrete argument types.
      # Lowering mints one constructor func per name from this.
      class Constructor
        getter name : String
        getter initialize_name : String?
        getter type : IR::Type
        getter param_types : Array(IR::Type)
        getter? reference : Bool

        def initialize(@name : String, @initialize_name : String?, @type : IR::Type, @param_types : Array(IR::Type), @reference : Bool = true)
        end

        def class_name : String
          type.name || type.to_s
        end
      end

      class ClosurePlan
        getter mode : BlockMode

        def initialize(@mode : BlockMode = BlockMode::Plain)
        end
      end

      class HandlerPlan
        enum Strategy
          RecoverDispatch
        end

        getter strategy : Strategy

        def initialize(@strategy : Strategy)
        end
      end

      abstract class Repr
      end

      # `T?` where `T` has a Go-pointer representation (a class this slice) —
      # spelled bare `*T`, with Go `nil` standing in for Crystal `nil`. No
      # carrier, no tag: the pointer is the value. The predicate is "member is
      # Go-pointer-repr", so `Channel(T)?`/`Exception?` extend it additively.
      class PointerRepr < Repr
        getter element : IR::Type

        def initialize(@element : IR::Type)
        end
      end

      # Chosen representation of Array(T). The element remains
      # structured; `reference` is the planning decision threaded into LIR.
      class ArrayRepr
        getter type : IR::Type
        getter element : IR::Type
        getter? reference : Bool

        def initialize(@type : IR::Type, @element : IR::Type, @reference : Bool)
        end
      end

      class HashRepr
        getter type : IR::Type
        getter? reference : Bool
        getter? ordered : Bool

        def initialize(@type : IR::Type, @reference : Bool, @ordered : Bool)
        end

        def key : IR::Type
          type.key_type || IR::Type.unknown
        end

        def value : IR::Type
          type.value_type || IR::Type.unknown
        end
      end

      class EnumRepr
        record Member, name : String, value : String, target_name : String

        getter type : IR::Type
        getter target_name : String
        getter base_type : IR::Type
        getter members : Array(Member)

        def initialize(@type : IR::Type, @target_name : String, @base_type : IR::Type, @members : Array(Member))
        end
      end

      enum EqualityStrategy
        Native
      end

      class CheckedArithmeticPlan
        getter strategy : IR::CheckedArithmeticStrategy

        def initialize(@strategy : IR::CheckedArithmeticStrategy)
        end
      end

      class ScalarStringificationPlan
        getter type : IR::Type
        getter presentation : IR::ScalarPresentation

        def initialize(@type : IR::Type, @presentation : IR::ScalarPresentation)
        end
      end

      # The chosen realization of a semantic collection-producing operation.
      # This is a class family so later evidence can add projections or streams
      # carrying their own data without turning a target into a graph planner.
      abstract class CollectionProduction
        getter type : IR::Type

        def initialize(@type : IR::Type)
        end
      end

      # Conservative fallback: produce the complete language-level collection
      # in its independently planned representation.
      class MaterializedCollection < CollectionProduction
      end

      # A collection result whose only proven consumer traverses exact string
      # segments once. The language-level Array remains the fallback in every
      # other use/profile; this plan permits lowering to commit a one-shot
      # source without changing String#split semantics globally.
      class StreamedCollection < CollectionProduction
      end

      # The chosen execution of a bodyful semantic collection operation. This
      # family covers producers, traversal, and terminals without conflating
      # their public capability with optimization legality.
      abstract class SemanticCollectionPlan
        getter result_type : IR::Type

        def initialize(@result_type : IR::Type)
        end
      end

      # Conservative execution: materialize every eager intermediate through
      # the retained ordinary Tango bodies, then invoke the terminal body.
      class MaterializeViaFallback < SemanticCollectionPlan
      end

      enum FusedCollectionTransformKind
        FilterKeep
        Map
      end

      record FusedCollectionTransform, operation : NodeId, kind : FusedCollectionTransformKind

      # One release-profile traversal selected from conservative collection
      # facts. Node identities retain the independently typed source,
      # transforms, and terminal for lowering; no target spelling enters the
      # plan.
      class FusedCollectionTraversal < SemanticCollectionPlan
        getter source : NodeId
        getter transforms : Array(FusedCollectionTransform)
        getter terminal : NodeId

        def initialize(result_type : IR::Type, @source : NodeId, @transforms : Array(FusedCollectionTransform), @terminal : NodeId)
          super(result_type)
        end
      end

      # The selected cardinality realization for one semantic NIR::Size.
      abstract class CardinalityPlan
        getter source_type : IR::Type

        def initialize(@source_type : IR::Type)
        end
      end

      class StoredCardinality < CardinalityPlan
        enum Source
          ArrayElements
          HashEntries
        end

        getter source : Source

        def initialize(source_type : IR::Type, @source : Source)
          super(source_type)
        end
      end

      class CodepointCardinality < CardinalityPlan
      end

      # Shared structured source/target relation for planning products that
      # commit behavior at a typed value boundary.
      abstract class TypeRelationPlan
        getter source : IR::Type
        getter target : IR::Type

        def initialize(@source : IR::Type, @target : IR::Type)
        end
      end

      class TypeTestPlan < TypeRelationPlan
        enum Strategy
          StaticTrue
          StaticFalse
          PointerNonNil
          PointerNil
          CarrierTag
          CarrierNil
        end

        getter strategy : Strategy

        def initialize(@strategy : Strategy, source : IR::Type, target : IR::Type)
          super(source, target)
        end
      end

      class CastPlan < TypeRelationPlan
        enum Strategy
          Passthrough
          PointerChecked
          CarrierChecked
        end

        getter strategy : Strategy

        def initialize(@strategy : Strategy, source : IR::Type, target : IR::Type)
          super(source, target)
        end
      end

      # A tagged-value carrier: a generated Go struct `{tag uint8; v<label> T; …}`.
      # Invariants:
      #   * `Nil` is always tag 0, so the struct's Go zero value IS nil —
      #     tag order is fixed here, decoupled from any `to_s` display order.
      #   * one payload field per non-`Nil` member, inlined — sum-of-widths.
      #   * every box constructs a FRESH literal, so inactive payloads stay zero
      #     and Go native `==` is correct.
      class CarrierRepr < Repr
        # A `Nil` variant has a nil payload and (by construction) tag 0.
        record Variant, label : String, tag : Int32, payload : IR::Type?

        getter name : String
        getter variants : Array(Variant)

        def initialize(@name : String, @variants : Array(Variant))
        end

        def variant_for(member : IR::Type) : Variant?
          variants.find { |variant| variant.payload == member }
        end

        def nil_variant : Variant?
          variants.find { |variant| variant.payload.nil? }
        end
      end

      # A planned carrier-to-carrier widening. Each source variant maps to the
      # same semantic member in the target carrier, with both concrete tags and
      # payload labels fixed here so lowering/targets never re-prove membership.
      class CarrierConversion < TypeRelationPlan
        getter mapping : IR::CarrierConversionMap

        def initialize(source : IR::Type, target : IR::Type, @mapping : IR::CarrierConversionMap)
          super(source, target)
        end
      end

      class Table
        property uncaught_exception : IR::UncaughtExceptionStrategy?
        getter calls = Hash(NodeId, CallPlan).new
        getter monomorphs = Hash(NodeId, DefPlan).new
        getter namespaces = Hash(NodeId, NamespacePlan).new
        getter constants = Hash(NodeId, ConstantPlan).new
        getter type_aliases = Hash(NodeId, TypeAliasPlan).new
        getter capability_dispatches = Hash(NodeId, Array(CapabilityDispatch)).new
        getter layouts = Hash(String, ClassLayout).new
        getter constructors = Hash(NodeId, Constructor).new
        getter closures = Hash(NodeId, ClosurePlan).new
        getter reprs = Hash(IR::Type, Repr).new
        getter arrays = Hash(IR::Type, ArrayRepr).new
        getter hashes = Hash(IR::Type, HashRepr).new
        getter enums = Hash(IR::Type, EnumRepr).new
        getter equalities = Hash(NodeId, EqualityStrategy).new
        getter checked_arithmetic = Hash(NodeId, CheckedArithmeticPlan).new
        getter type_tests = Hash(NodeId, TypeTestPlan).new
        getter casts = Hash(NodeId, CastPlan).new
        getter handlers = Hash(NodeId, HandlerPlan).new
        getter carrier_conversions = Hash(NodeId, CarrierConversion).new
        getter scalar_stringifications = Hash(NodeId, ScalarStringificationPlan).new
        getter semantic_collections = Hash(NodeId, SemanticCollectionPlan).new
        getter collection_productions = Hash(NodeId, CollectionProduction).new
        getter cardinalities = Hash(NodeId, CardinalityPlan).new
      end
    end
  end
end
