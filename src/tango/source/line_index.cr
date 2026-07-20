module Tango
  module Source
    class LineIndex
      getter line_starts : Array(Int32)

      def initialize(@code : String)
        starts = [0]
        bytes = @code.to_slice
        index = 0
        while index < bytes.size
          starts << index + 1 if bytes[index] == '\n'.ord
          index += 1
        end
        @line_starts = starts
      end

      def line_col(offset : Int32) : {Int32, Int32}
        offset = offset.clamp(0, @code.bytesize)
        index = line_index(offset)
        line_start = @line_starts[index]
        {index + 1, @code.byte_slice(line_start, offset - line_start).size + 1}
      end

      def byte_line_col(offset : Int32) : {Int32, Int32}
        offset = offset.clamp(0, @code.bytesize)
        index = line_index(offset)
        {index + 1, offset - @line_starts[index] + 1}
      end

      def byte_offset_at(line : Int32, column : Int32) : Int32
        index = (line - 1).clamp(0, @line_starts.size - 1)
        line_start = @line_starts[index]
        line_end = @line_starts[index + 1]? || @code.bytesize
        line_end -= 1 if line_end > line_start && @code.byte_at(line_end - 1) == '\n'.ord
        line_end -= 1 if line_end > line_start && @code.byte_at(line_end - 1) == '\r'.ord
        (line_start + (column - 1)).clamp(line_start, line_end)
      end

      private def line_index(offset : Int32) : Int32
        low = 0
        high = @line_starts.size - 1
        while low < high
          mid = (low + high + 1) // 2
          if @line_starts[mid] <= offset
            low = mid
          else
            high = mid - 1
          end
        end
        low
      end
    end
  end
end
