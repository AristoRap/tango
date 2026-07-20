module Tango
  module Source
    struct Range
      getter path : String
      getter start_offset : Int32
      getter end_offset : Int32
      getter line : Int32?
      getter column : Int32?

      def initialize(@path : String, @start_offset : Int32, @end_offset : Int32, @line : Int32? = nil, @column : Int32? = nil)
      end

      def self.point(path : String, offset : Int32) : self
        new(path, offset, offset + 1)
      end

      def length : Int32
        @end_offset - @start_offset
      end

      def contains?(path : String, offset : Int32) : Bool
        @path == path && @start_offset <= offset < @end_offset
      end

      def to_s(io : IO) : Nil
        io << @path << ':' << @start_offset << "..." << @end_offset
      end
    end
  end
end
