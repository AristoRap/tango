module Tango
  module Frontend
    module Crystal
      # Maps Crystal compiler locations back to every Tango project source.
      # Native macro expansion uses VirtualFile locations, so generated
      # declarations recover the real invocation token through the same seam.
      module SourceLocations
        private def source_node?(node : ::Crystal::ASTNode) : Bool
          !source_location(node.location).nil?
        end

        private def entry_source_node?(node : ::Crystal::ASTNode) : Bool
          location = source_location(node.location)
          location.try(&.filename) == @source.entrypoint.path
        end

        private def span(node : ::Crystal::ASTNode) : Source::Range?
          source_range(node.location)
        end

        private def name_span(location : ::Crystal::Location?, name : String) : Source::Range?
          identifier = name.ends_with?('=') ? name.rchop('=') : name
          if range = source_range(location, identifier.bytesize)
            source = @source.file?(range.path)
            spelling = source.try(&.code.byte_slice(range.start_offset, range.length))
            return range if spelling == identifier
          end
          declaration_name_span(location, name)
        end

        private def path_name_span(node : ::Crystal::Path) : Source::Range?
          member = node.names.last
          prefix_size = node.names[0...-1].sum(&.bytesize) + (node.names.size - 1) * 2
          full_size = prefix_size + member.bytesize
          range = source_range(node.location, full_size)
          return nil unless range
          column = range.column.try { |value| value + prefix_size }
          Source::Range.new(range.path, range.start_offset + prefix_size, range.end_offset, range.line, column)
        end

        # Normal source nodes and names share this guard. Generated declaration
        # names retain their separate expansion-location fallback below.
        private def source_range(location : ::Crystal::Location?, size : Int32 = 1) : Source::Range?
          source = source_location(location)
          return nil unless source

          source_file = @source.file?(source.filename.as(String))
          source_file.try do |file|
            column = file.byte_column_at(source.line_number, source.column_number)
            file.range_at(source.line_number, column, size)
          end
        end

        private def declaration_name_span(location : ::Crystal::Location?, name : String) : Source::Range?
          expanded = expansion_location(location)
          return nil unless expanded

          source = source_file(expanded)
          return nil unless source

          identifier = name.ends_with?('=') ? name.rchop('=') : name
          line_start = source.line_index.line_starts[expanded.line_number - 1]?
          return nil unless line_start
          line_end = source.line_index.line_starts[expanded.line_number]? || source.code.bytesize
          source_line = source.code.byte_slice(line_start, line_end - line_start)
          limit = source_line.index('=') || source_line.bytesize
          offset = 0
          found = nil
          while index = source_line.index(identifier, offset)
            break if index >= limit
            before = index > 0 ? source_line.byte_at(index - 1) : nil
            after_index = index + identifier.bytesize
            after = after_index < source_line.bytesize ? source_line.byte_at(after_index) : nil
            found = index unless identifier_byte?(before) || identifier_byte?(after)
            offset = index + identifier.bytesize
          end
          return nil unless found

          source.range_at(expanded.line_number, found + 1, identifier.bytesize)
        end

        private def identifier_byte?(byte : UInt8?) : Bool
          return false unless byte
          byte.in?('a'.ord.to_u8..'z'.ord.to_u8) ||
            byte.in?('A'.ord.to_u8..'Z'.ord.to_u8) ||
            byte.in?('0'.ord.to_u8..'9'.ord.to_u8) ||
            byte == '_'.ord
        end

        private def source_location(location : ::Crystal::Location?) : ::Crystal::Location?
          return nil unless location
          filename = location.filename
          return nil unless filename.is_a?(String) && @source.file?(filename)

          location
        end

        private def source_file(location : ::Crystal::Location) : Source::File?
          filename = location.filename
          filename.is_a?(String) ? @source.file?(filename) : nil
        end

        private def expansion_location(location : ::Crystal::Location?) : ::Crystal::Location?
          return nil unless location
          expanded = location.expanded_location
          return nil unless expanded
          filename = expanded.filename
          return nil unless filename.is_a?(String) && @source.file?(filename)

          expanded
        end

        private def expansion_span(location : ::Crystal::Location?) : Source::Range?
          expanded = expansion_location(location)
          return nil unless expanded
          source = source_file(expanded)
          return nil unless source

          column = source.byte_column_at(expanded.line_number, expanded.column_number)
          source.range_at(expanded.line_number, column)
        end
      end
    end
  end
end
