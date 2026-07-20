module Tango
  module IR
    # Structured, union-capable type identity — the single carrier of "what
    # type is this?" across every phase, replacing the flat `type_name : String?`
    # convention. Crystal-agnostic and Go-agnostic: it lives in `ir/` and knows
    # neither the frontend that builds it nor the target that spells it. The
    # point is that a union carries its members structurally instead of being
    # erased to the string "(Int32 | Nil)" — that erasure is what would force a
    # per-tool sidecar later.
    class Type
      # Minimal and extensible: Symbol joins when an example forces it. `Char`
      # is a Unicode code point, kept distinct from String as Crystal does.
      # `Class` is a reference type carrying its name. `Null` is the `Nil`
      # type — named `Null` internally so its generated `.null?` predicate
      # can't shadow `Object#nil?`; it still spells "Nil". `Float` is
      # Float64-only until a Float32 example forces a width axis.
      enum Family
        Int
        Float
        Bool
        Char
        String
        Enum
        Array
        Hash
        Proc
        Null
        Class
        Union
        Unknown
      end

      # Numeric width as an enum so int identity is total (name + width) rather
      # than a re-parsed string. Each width enters lowering only when a driving
      # example forces its target spelling and runtime semantics.
      enum Width
        I8
        I16
        I32
        I64
        U8
        U16
        U32
        U64

        def bits : Int32
          case self
          in I8, U8   then 8
          in I16, U16 then 16
          in I32, U32 then 32
          in I64, U64 then 64
          end
        end

        def signed? : Bool
          case self
          in I8, I16, I32, I64 then true
          in U8, U16, U32, U64 then false
          end
        end

        # The Crystal spelling — "Int32", "UInt8" — so `to_s`/mangle reproduce
        # today's names verbatim.
        def crystal_name : String
          "#{signed? ? "Int" : "UInt"}#{bits}"
        end
      end

      getter family : Family
      getter width : Width?
      getter name : String?
      getter members : Array(Type)
      # Structured generic arguments of a `Class` type: `Channel(Int32)` keeps
      # `Int32` here instead of erasing to the name string "Channel(Int32)". The
      # same reasoning as `members` for unions — a downstream phase that needs
      # the element (the target spelling `chan T`) reads it structurally rather
      # than re-parsing a name. Empty for a non-generic class.
      getter type_args : Array(Type)

      def initialize(@family : Family, @width : Width? = nil, @name : String? = nil, @members : Array(Type) = [] of Type, @type_args : Array(Type) = [] of Type)
      end

      # The sentinel `Nil` member/value.
      NIL                 = new(Family::Null)
      EXCEPTION_ROOT_NAME = "Exception"
      NO_RETURN_NAME      = "NoReturn"

      def self.int(width : Width) : Type
        new(Family::Int, width: width)
      end

      def self.float64 : Type
        new(Family::Float)
      end

      def self.bool : Type
        new(Family::Bool)
      end

      def self.char : Type
        new(Family::Char)
      end

      def self.string : Type
        new(Family::String)
      end

      def self.enumeration(name : String) : Type
        new(Family::Enum, name: name)
      end

      def self.array(element : Type) : Type
        new(Family::Array, type_args: [element])
      end

      def self.hash(key : Type, value : Type) : Type
        new(Family::Hash, type_args: [key, value])
      end

      # A block/proc's concrete signature. The return occupies the final type
      # argument; Nil is kept explicitly so `T ->` and `T -> U` remain distinct
      # monomorphization keys without flattening the arrow into a string.
      def self.proc(param_types : Array(Type), return_type : Type?) : Type
        new(Family::Proc, type_args: param_types + [return_type || NIL])
      end

      def self.klass(name : String, type_args : Array(Type) = [] of Type) : Type
        new(Family::Class, name: name, type_args: type_args)
      end

      def self.unknown : Type
        new(Family::Unknown)
      end

      # The single canonicalizer for a union: flatten nested unions, dedup by
      # identity, render `Nil` last (display only — tag assignment order is a
      # planning concern, decoupled from this), and collapse degenerate cases
      # (0 members -> Unknown, 1 member -> the bare scalar). The collapse is
      # what makes `without_nil` on {T, Nil} decay to T.
      def self.union(members : Array(Type)) : Type
        flat = [] of Type
        members.each do |member|
          if member.union?
            member.members.each { |inner| flat << inner }
          else
            flat << member
          end
        end

        unique = [] of Type
        flat.each { |member| unique << member unless unique.includes?(member) }

        nils, rest = unique.partition(&.nil_type?)
        ordered = rest + nils

        case ordered.size
        when 0 then unknown
        when 1 then ordered.first
        else        new(Family::Union, members: ordered)
        end
      end

      def union? : Bool
        family.union?
      end

      # The `Nil` type. Named `nil_type?` (not `nil?`) so it never collides with
      # the built-in Object#nil?; the family member is `Null` for the same reason.
      def nil_type? : Bool
        family.null?
      end

      def reference? : Bool
        family.class? || family.array? || family.hash?
      end

      def enum? : Bool
        family.enum?
      end

      def array? : Bool
        family.array?
      end

      def hash? : Bool
        family.hash?
      end

      def proc? : Bool
        family.proc?
      end

      # Language-level sentinels shared by neutral semantic phases. Target
      # runtime helper names remain target-owned and do not belong here.
      def exception_root? : Bool
        name == EXCEPTION_ROOT_NAME
      end

      def no_return? : Bool
        name == NO_RETURN_NAME
      end

      def proc_param_types : Array(Type)
        proc? ? type_args[0...-1] : [] of Type
      end

      def proc_return_type : Type?
        return nil unless proc?
        type = type_args.last?
        type.try(&.nil_type?) ? nil : type
      end

      def element_type : Type?
        array? ? type_args.first? : nil
      end

      def key_type : Type?
        hash? ? type_args.first? : nil
      end

      def value_type : Type?
        hash? ? type_args[1]? : nil
      end

      # A view over members, never a stored flag: a union that admits `Nil`.
      def nilable? : Bool
        union? && members.any?(&.nil_type?)
      end

      def with_nil : Type
        Type.union(union_members + [NIL])
      end

      def without_nil : Type
        Type.union(union_members.reject(&.nil_type?))
      end

      private def union_members : Array(Type)
        union? ? members : [self]
      end

      def to_s(io : IO) : Nil
        case family
        in .int?
          io << (width || Width::I32).crystal_name
        in .float?
          io << "Float64"
        in .bool?
          io << "Bool"
        in .char?
          io << "Char"
        in .string?
          io << "String"
        in .enum?
          io << (name || "?")
        in .array?
          io << "Array(" << (element_type || Type.unknown) << ')'
        in .hash?
          io << "Hash(" << (key_type || Type.unknown) << ", " << (value_type || Type.unknown) << ')'
        in .proc?
          io << '(' << proc_param_types.join(", ") << ") -> " << (proc_return_type || "Nil")
        in .null?
          io << "Nil"
        in .class?
          io << (name || "?")
          unless type_args.empty?
            io << '('
            type_args.each_with_index do |arg, index|
              io << ", " if index > 0
              arg.to_s(io)
            end
            io << ')'
          end
        in .unknown?
          io << "?"
        in .union?
          non_nil = members.reject(&.nil_type?)
          if nilable? && non_nil.size == 1
            non_nil.first.to_s(io)
            io << '?'
          else
            io << members.map(&.to_s).join(" | ")
          end
        end
      end

      # User-facing semantic type spelling. Unlike `to_s`, which retains source
      # shorthand for compact dumps, this preserves every union member so hover
      # can show what the surface shorthand leaves implicit.
      def to_semantic_s : String
        String.build { |io| to_semantic_s(io) }
      end

      def to_semantic_s(io : IO) : Nil
        case family
        in .array?
          io << "Array("
          (element_type || Type.unknown).to_semantic_s(io)
          io << ')'
        in .hash?
          io << "Hash("
          (key_type || Type.unknown).to_semantic_s(io)
          io << ", "
          (value_type || Type.unknown).to_semantic_s(io)
          io << ')'
        in .proc?
          io << '('
          proc_param_types.each_with_index do |type, index|
            io << ", " if index > 0
            type.to_semantic_s(io)
          end
          io << ") -> "
          (proc_return_type || Type::NIL).to_semantic_s(io)
        in .class?
          io << (name || "?")
          unless type_args.empty?
            io << '('
            type_args.each_with_index do |type, index|
              io << ", " if index > 0
              type.to_semantic_s(io)
            end
            io << ')'
          end
        in .union?
          io << '('
          members.each_with_index do |type, index|
            io << " | " if index > 0
            type.to_semantic_s(io)
          end
          io << ')'
        in .int?, .float?, .bool?, .char?, .string?, .enum?, .null?, .unknown?
          to_s(io)
        end
      end

      def_equals_and_hash family, width, name, members, type_args
    end

    # The shared qualified identity behind external callable and type bindings.
    # Callable-specific receiver dispatch and type-specific representation stay
    # on their respective owners; language/package/name parsing happens once.
    class ExternalBinding
      getter language : String
      getter package_name : String?
      getter name : String?

      def initialize(@language : String, @package_name : String? = nil, @name : String? = nil)
      end

      def self.qualified(language : String, value : String) : self
        package_name, separator, name = value.rpartition('.')
        package_name = nil if separator.empty?
        new(language, package_name, name)
      end
    end

    # A source-declared binding from a Tango type to an external target type.
    # The shape is typed so no phase parses a target string to rediscover
    # pointer/channel policy.
    class ExternalType
      enum Shape
        NativeChannel
        NamedPointer
        NamedValue
      end

      getter type : Type
      getter binding : ExternalBinding
      getter shape : Shape

      def initialize(@type : Type, @binding : ExternalBinding, @shape : Shape)
      end

      def pointer? : Bool
        shape.native_channel? || shape.named_pointer?
      end
    end

    # A proc type `(A, B) -> R` shared by normalized and lowered IR. The
    # signature is language data; neither phase adds representation policy.
    record ProcSignature, param_types : Array(Type), return_type : Type? do
      def to_type : Type
        Type.proc(param_types, return_type)
      end
    end

    # A named, typed field shared by neutral semantic representations. Phase
    # boundaries may copy the containing array, but not reinvent field identity.
    record Field, name : String, type : Type
  end
end
