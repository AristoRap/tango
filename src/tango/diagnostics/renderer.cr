module Tango
  module Diagnostics
    # Renders shared diagnostics with source context for terminal consumers.
    # Source positions remain byte-based in the compiler and are resolved to
    # display columns here, at the presentation boundary.
    module Renderer
      private RED    = "\e[1;31m"
      private YELLOW = "\e[1;33m"
      private BLUE   = "\e[1;34m"
      private DIM    = "\e[2m"
      private RESET  = "\e[0m"

      def self.render(
        source : String,
        diagnostic : Diagnostic,
        path : String = "<source>",
        color : Bool = false,
        index : Source::LineIndex = Source::LineIndex.new(source),
      ) : String
        start_offset, end_offset = offsets(source, diagnostic, path, index)
        start_line, start_column = index.line_col(start_offset)
        end_line, end_column = index.line_col(end_offset)
        line_text = line_at(source, start_line, index)
        width = caret_width(start_column, end_column, start_line == end_line, line_text)
        marker_padding = marker_padding(line_text, start_column)
        label, hue = label_for(diagnostic.severity)
        number = start_line.to_s
        gutter = " " * number.size
        bar = paint("|", BLUE, color)

        String.build do |io|
          io << paint(label, hue, color) << ": " << diagnostic.message << '\n'
          io << gutter << paint("--> #{path}:#{start_line}:#{start_column}", DIM, color) << '\n'
          io << gutter << ' ' << bar << '\n'
          io << paint(number, BLUE, color) << ' ' << bar << ' ' << line_text << '\n'
          io << gutter << ' ' << bar << ' ' << marker_padding << paint("^" * width, hue, color)

          diagnostic.related.each do |related_range, note|
            related_path, related_line, related_column = related_location(related_range, path, index)
            io << '\n' << gutter << ' ' << paint("= note:", BLUE, color) << ' ' << note <<
              ' ' << paint("(#{related_path}:#{related_line}:#{related_column})", DIM, color)
          end

          diagnostic.hints.each do |hint|
            io << '\n' << gutter << ' ' << paint("= help:", BLUE, color) << ' ' << hint
          end
        end
      end

      private def self.offsets(
        source : String,
        diagnostic : Diagnostic,
        path : String,
        index : Source::LineIndex,
      ) : {Int32, Int32}
        if range = diagnostic.range
          if range.path == path
            start_offset = range.start_offset.clamp(0, source.bytesize)
            end_offset = range.end_offset.clamp(start_offset, source.bytesize)
            return {start_offset, end_offset}
          end
        end

        start_offset = index.byte_offset_at(diagnostic.line, diagnostic.column)
        end_offset = (start_offset + diagnostic.size).clamp(start_offset, source.bytesize)
        {start_offset, end_offset}
      end

      private def self.label_for(severity : Diagnostic::Severity) : {String, String}
        case severity
        in .error?   then {"error", RED}
        in .warning? then {"warning", YELLOW}
        end
      end

      private def self.paint(text : String, code : String, color : Bool) : String
        color ? "#{code}#{text}#{RESET}" : text
      end

      private def self.line_at(source : String, line_no : Int32, index : Source::LineIndex) : String
        line_index = line_no - 1
        return "" unless 0 <= line_index < index.line_starts.size

        start_offset = index.line_starts[line_index]
        end_offset = index.line_starts[line_index + 1]? || source.bytesize
        end_offset -= 1 if end_offset > start_offset && source.byte_at(end_offset - 1) == '\n'.ord
        end_offset -= 1 if end_offset > start_offset && source.byte_at(end_offset - 1) == '\r'.ord
        source.byte_slice(start_offset, end_offset - start_offset)
      end

      # Preserve tabs before the marker so terminal tab stops stay aligned.
      private def self.marker_padding(line_text : String, start_column : Int32) : String
        prefix_size = {start_column - 1, line_text.size}.min
        String.build do |io|
          line_text[0, prefix_size].each_char do |char|
            io << (char == '\t' ? '\t' : ' ')
          end
        end
      end

      # A multi-line span is represented by its first line. Single-line spans
      # are clamped to visible source, while a point at end-of-line still gets
      # one caret.
      private def self.caret_width(
        start_column : Int32,
        end_column : Int32,
        single_line : Bool,
        line_text : String,
      ) : Int32
        available = {line_text.size - (start_column - 1), 0}.max
        requested = single_line ? end_column - start_column : available
        clamped = {requested, available}.min
        {clamped, 1}.max
      end

      private def self.related_location(
        range : Source::Range,
        source_path : String,
        index : Source::LineIndex,
      ) : {String, Int32, Int32}
        if range.path == source_path
          line, column = index.line_col(range.start_offset)
          {range.path, line, column}
        else
          {range.path, range.line || 1, range.column || 1}
        end
      end
    end
  end
end
