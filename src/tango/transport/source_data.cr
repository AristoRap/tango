module Tango
  module Transport
    @[JSON::Serializable::Options(emit_nulls: true)]
    class FileData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter path : String
      getter code : String
      getter identity : String
      getter stable_path : Bool

      def initialize(file : Source::File)
        @path = file.path
        @code = file.code
        @identity = file.identity
        @stable_path = file.stable_path?
      end

      def to_file : Source::File
        Source::File.new(@path, @code, @identity, @stable_path)
      end
    end

    @[JSON::Serializable::Options(emit_nulls: true)]
    class RequireData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter from : String
      getter request : String
      getter range : RangeData

      def initialize(directive : Source::RequireDirective)
        @from = directive.from
        @request = directive.request
        @range = RangeData.new(directive.range)
      end

      def to_directive : Source::RequireDirective
        Source::RequireDirective.new(@from, @request, @range.to_range)
      end
    end

    @[JSON::Serializable::Options(emit_nulls: true)]
    class EdgeData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter from : String
      getter request : String
      getter to : String
      getter range : RangeData

      def initialize(edge : Source::RequireEdge)
        @from = edge.from
        @request = edge.request
        @to = edge.to
        @range = RangeData.new(edge.range)
      end

      def to_edge : Source::RequireEdge
        Source::RequireEdge.new(@from, @request, @to, @range.to_range)
      end
    end
  end
end
