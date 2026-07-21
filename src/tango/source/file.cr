module Tango
  module Source
    class File
      getter path : String
      getter code : String
      getter identity : String
      getter line_index : LineIndex
      getter? stable_path : Bool

      def self.canonical_identity(path : String) : String
        expanded = ::File.expand_path(path)
        ::File.exists?(expanded) ? ::File.realpath(expanded) : expanded
      rescue ex : ::File::Error
        ::File.expand_path(path)
      end

      def self.canonical(path : String, code : String, stable_path : Bool = true) : self
        new(path, code, canonical_identity(path), stable_path)
      end

      def initialize(
        @path : String,
        @code : String,
        identity : String? = nil,
        @stable_path : Bool = true,
      )
        @identity = identity || @path
        @line_index = LineIndex.new(@code)
      end

      def range_at(line : Int32, column : Int32, size : Int32 = 1) : Range
        start = @line_index.byte_offset_at(line, column)
        Range.new(@path, start, (start + size).clamp(start, @code.bytesize), line, column)
      end

      # Crystal source locations count characters, while Tango source ranges
      # use 1-based byte columns. Keep that conversion at the source boundary
      # so every frontend projection agrees in the presence of Unicode.
      def byte_column_at(line : Int32, character_column : Int32) : Int32
        wanted = Math.max(character_column - 1, 0)
        start = @line_index.line_starts[line - 1]? || return 1
        finish = @line_index.line_starts[line]? || @code.bytesize
        source_line = @code.byte_slice(start, finish - start)
        bytes = 0
        seen = 0
        source_line.each_char do |char|
          break if seen >= wanted
          bytes += char.bytesize
          seen += 1
        end
        bytes + 1
      end

      # Crystal occasionally reports an actionable semantic error at a literal's
      # first byte with a zero/one-byte span. Preserve a wider compiler span as
      # authoritative; otherwise recover a complete quoted or numeric literal
      # for every shared diagnostic consumer. Identifiers retain Crystal's
      # original point range: a one-character identifier span may be deliberate.
      def token_range_at(line : Int32, column : Int32, reported_size : Int32 = 0) : Range
        return range_at(line, column, reported_size) if reported_size > 1

        start = @line_index.byte_offset_at(line, column)
        Range.new(@path, start, token_end(start), line, column)
      end

      # Source-graph diagnostics begin at the `require` keyword. This lets the
      # shared diagnostic layer select the user-supplied quoted request without
      # duplicating parsing or path resolution.
      def require_path_range_at(line : Int32, column : Int32) : Range?
        start = @line_index.byte_offset_at(line, column)
        keyword = "require"
        return unless @code.byte_slice(start, keyword.bytesize) == keyword

        bytes = @code.to_slice
        index = start + keyword.bytesize
        while byte = bytes[index]?
          break unless byte == ' '.ord.to_u8 || byte == '\t'.ord.to_u8
          index += 1
        end
        return unless byte = bytes[index]?
        return unless byte == '"'.ord.to_u8 || byte == '\''.ord.to_u8

        path_line, path_column = @line_index.byte_line_col(index)
        Range.new(@path, index, token_end(index), path_line, path_column)
      end

      private def token_end(start : Int32) : Int32
        bytes = @code.to_slice
        byte = bytes[start]?
        return (start + 1).clamp(start, @code.bytesize) unless byte

        if byte == '"'.ord.to_u8 || byte == '\''.ord.to_u8
          return quoted_token_end(bytes, start, byte)
        end

        return (start + 1).clamp(start, @code.bytesize) unless numeric_byte?(byte)

        index = start
        while current = bytes[index]?
          break unless identifier_or_number_byte?(current)
          index += 1
        end
        index
      end

      private def quoted_token_end(bytes : Bytes, start : Int32, quote : UInt8) : Int32
        index = start + 1
        escaped = false
        while current = bytes[index]?
          index += 1
          if current == quote && !escaped
            return index
          end
          escaped = current == '\\'.ord.to_u8 && !escaped
          escaped = false unless current == '\\'.ord.to_u8
        end
        index
      end

      private def identifier_or_number_byte?(byte : UInt8) : Bool
        byte.in?('a'.ord.to_u8..'z'.ord.to_u8) ||
          byte.in?('A'.ord.to_u8..'Z'.ord.to_u8) ||
          byte.in?('0'.ord.to_u8..'9'.ord.to_u8) ||
          byte == '_'.ord.to_u8
      end

      private def numeric_byte?(byte : UInt8) : Bool
        byte.in?('0'.ord.to_u8..'9'.ord.to_u8)
      end
    end
  end
end
