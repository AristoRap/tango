module Tango
  module IR
    module LIR
      class Param
        enum Repr
          Native
          ExceptionInterface
        end

        getter name : String
        getter type : IR::Type?
        getter proc_signature : ProcSignature?
        getter? by_ref : Bool
        getter repr : Repr

        def initialize(@name : String, @type : IR::Type?, @proc_signature : ProcSignature? = nil, @by_ref : Bool = false, @repr : Repr = Repr::Native)
        end
      end

      class Func
        getter name : String
        getter params : Array(Param)
        getter return_type : IR::Type?
        getter body : Array(Stmt)
        getter loc : SourceLoc?

        def initialize(@name : String, @params : Array(Param), @return_type : IR::Type?, @body : Array(Stmt), @loc : SourceLoc? = nil)
        end
      end

      class Global
        getter name : String
        getter type : IR::Type
        getter value : Value
        getter loc : SourceLoc?

        def initialize(@name : String, @type : IR::Type, @value : Value, @loc : SourceLoc? = nil)
        end
      end

      # A struct type declaration hoisted from a class layout. Neither a Value
      # nor a Stmt — a top-level declaration, like Func. `reference` carries the
      # planned representation: a reference type is spelled and allocated as a
      # pointer by the target, a value type inline.
      class StructType
        getter type : IR::Type
        getter name : String
        getter fields : Array(IR::Field)
        getter reference : Bool
        getter exception_ancestors : Array(String)
        getter? identity_padding : Bool

        def initialize(@name : String, @fields : Array(IR::Field), @reference : Bool, @exception_ancestors : Array(String) = [] of String, @identity_padding : Bool = false, @type : IR::Type = IR::Type.klass(name))
        end

        def exception_runtime? : Bool
          !exception_ancestors.empty?
        end
      end

      # A carrier struct declaration hoisted from a union's chosen representation
      # (the `CarrierRepr` mirror, self-contained so the target reads LIR, not
      # plans). `type` is the union it reps — the key the target resolves Box /
      # Unbox / NilCheck against. Emitted as a Go struct `{tag uint8; v<label> T; …}`.
      class UnionType
        record Variant, label : String, tag : Int32, payload : IR::Type?

        getter type : IR::Type
        getter name : String
        getter variants : Array(Variant)

        def initialize(@type : IR::Type, @name : String, @variants : Array(Variant))
        end
      end

      # A self-contained carrier widening declaration copied from planning.
      # Labels and tags are concrete representation data, so the target only
      # spells the function and never consults facts/plans or recomputes maps.
      class UnionConversion
        getter source : IR::Type
        getter target : IR::Type
        getter mapping : IR::CarrierConversionMap

        def initialize(@source : IR::Type, @target : IR::Type, @mapping : IR::CarrierConversionMap)
        end
      end

      # The planned representation of one concrete Array(T), copied into LIR
      # so the target reads no planning table and only spells the decision.
      class ArrayType
        getter type : IR::Type
        getter element : IR::Type
        getter? reference : Bool

        def initialize(@type : IR::Type, @element : IR::Type, @reference : Bool)
        end
      end

      class HashType
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

      class EnumType
        record Member, name : String, value : String, target_name : String

        getter type : IR::Type
        getter target_name : String
        getter base_type : IR::Type
        getter members : Array(Member)

        def initialize(@type : IR::Type, @target_name : String, @base_type : IR::Type, @members : Array(Member))
        end
      end

      class Program
        getter uncaught_exception : IR::UncaughtExceptionStrategy
        getter functions : Array(Func)
        getter body : Array(Stmt)
        getter types : Array(StructType)
        getter unions : Array(UnionType)
        getter arrays : Array(ArrayType)
        getter hashes : Array(HashType)
        getter external_types : Array(IR::ExternalType)
        getter conversions : Array(UnionConversion)
        getter enums : Array(EnumType)
        getter globals : Array(Global)

        def initialize(@body : Array(Stmt), @functions : Array(Func) = [] of Func, @types : Array(StructType) = [] of StructType, @unions : Array(UnionType) = [] of UnionType, @arrays : Array(ArrayType) = [] of ArrayType, @hashes : Array(HashType) = [] of HashType, @external_types : Array(IR::ExternalType) = [] of IR::ExternalType, @conversions : Array(UnionConversion) = [] of UnionConversion, @uncaught_exception : IR::UncaughtExceptionStrategy = IR::UncaughtExceptionStrategy::CrystalStyle, @enums : Array(EnumType) = [] of EnumType, @globals : Array(Global) = [] of Global)
        end
      end
    end
  end
end
