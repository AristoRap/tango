module Tango
  module Lsp
    # Converts Tango's source locations (1-based line + byte column) to
    # LSP positions in the negotiated encoding. Correct position encoding is
    # protocol plumbing, not a feature — every LSP response needs it, even
    # the diagnostics-only V0.
    module Position
      alias LspPosition = NamedTuple(line: Int32, character: Int32)
      alias LspRange = NamedTuple(start: LspPosition, end: LspPosition)

      enum Encoding
        UTF8
        UTF16
        UTF32
      end

      def self.encoding_name(encoding : Encoding) : String
        case encoding
        in .utf8?  then "utf-8"
        in .utf16? then "utf-16"
        in .utf32? then "utf-32"
        end
      end

      class LineIndex
        @lines : Array(String)

        def initialize(source : String)
          @lines = source.split('\n', remove_empty: false).map do |line|
            line.ends_with?("\r") ? line[0, line.size - 1] : line
          end
        end

        def range(line_number : Int32?, column_number : Int32?, size : Int32?, encoding : Encoding) : LspRange
          line = line_number || 1
          column = column_number || 1
          line = 1 if line < 1
          column = 1 if column < 1

          source_line = @lines[line - 1]? || ""
          width = highlight_width(size, source_line, column)
          start_position = position(line, column, encoding)
          end_position = position(line, column + width, encoding)

          {
            start: start_position,
            end:   end_position,
          }
        end

        def position(line_number : Int32?, column_number : Int32?, encoding : Encoding) : LspPosition
          line = line_number || 1
          column = column_number || 1
          line = 1 if line < 1
          column = 1 if column < 1

          source_line = @lines[line - 1]? || ""
          {line: line - 1, character: encoded_character(source_line, column, encoding)}
        end

        def tango_column(lsp_line : Int32, lsp_character : Int32, encoding : Encoding) : Int32
          line = lsp_line + 1
          line = 1 if line < 1
          character = lsp_character < 0 ? 0 : lsp_character

          source_line = @lines[line - 1]? || ""
          decoded_column(source_line, character, encoding)
        end

        def full_range(encoding : Encoding) : LspRange
          end_line = @lines.size
          end_column = (@lines.last?.try(&.bytesize) || 0) + 1
          {
            start: {line: 0, character: 0},
            end:   position(end_line, end_column, encoding),
          }
        end

        private def highlight_width(size : Int32?, source_line : String, column : Int32) : Int32
          remaining = source_line.bytesize - (column - 1)
          return 0 if remaining <= 0

          width = size || 1
          width = 1 if width < 1
          width > remaining ? remaining : width
        end

        private def encoded_character(source_line : String, tango_column : Int32, encoding : Encoding) : Int32
          wanted_bytes = tango_column - 1
          return 0 if wanted_bytes <= 0

          seen_bytes = 0
          encoded = 0
          source_line.each_char do |char|
            break if seen_bytes >= wanted_bytes
            break if seen_bytes + char.bytesize > wanted_bytes

            seen_bytes += char.bytesize
            encoded += encoded_width(char, encoding)
          end
          encoded
        end

        private def decoded_column(source_line : String, lsp_character : Int32, encoding : Encoding) : Int32
          return 1 if lsp_character <= 0

          encoded = 0
          column = 1
          source_line.each_char do |char|
            width = encoded_width(char, encoding)
            return column if encoded + width > lsp_character

            encoded += width
            column += char.bytesize
            return column if encoded == lsp_character
          end
          column
        end

        private def encoded_width(char : Char, encoding : Encoding) : Int32
          case encoding
          in .utf8?
            char.bytesize
          in .utf16?
            char.ord > 0xFFFF ? 2 : 1
          in .utf32?
            1
          end
        end
      end
    end
  end
end
