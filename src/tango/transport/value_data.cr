module Tango
  # Generated JSON representations shared by process and semantic-bundle
  # boundaries. Compiler-domain objects remain wire-annotation free.
  module Transport
    @[JSON::Serializable::Options(emit_nulls: true)]
    class RangeData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter path : String
      getter start_offset : Int32
      getter end_offset : Int32
      getter line : Int32?
      getter column : Int32?

      def initialize(range : Source::Range)
        @path = range.path
        @start_offset = range.start_offset
        @end_offset = range.end_offset
        @line = range.line
        @column = range.column
      end

      def to_range : Source::Range
        Source::Range.new(@path, @start_offset, @end_offset, @line, @column)
      end
    end

    @[JSON::Serializable::Options(emit_nulls: true)]
    class TypeData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter family : String
      getter width : String?
      getter name : String?
      getter members : Array(TypeData)
      getter type_args : Array(TypeData)

      def initialize(type : IR::Type)
        @family = type.family.to_s
        @width = type.width.try(&.to_s)
        @name = type.name
        @members = type.members.map { |member| TypeData.new(member).as(TypeData) }
        @type_args = type.type_args.map { |argument| TypeData.new(argument).as(TypeData) }
      end

      def to_type : IR::Type
        IR::Type.new(
          IR::Type::Family.parse(@family),
          @width.try { |value| IR::Type::Width.parse(value) },
          @name,
          @members.map(&.to_type),
          @type_args.map(&.to_type)
        )
      end
    end
  end
end
