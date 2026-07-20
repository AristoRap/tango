module Tango
  module Compiler
    module Editor
      # Protocol-neutral safe-rename query. It consumes only the immutable
      # editor projection: symbol families decide identity membership, while
      # source slices verify the exact spelling each edit will replace.
      module Rename
        record Preparation,
          range : Source::Range,
          placeholder : String,
          family : Index::SymbolFamily

        alias Edit = Source::Edit
        record Plan, edits : Array(Edit), family : Index::SymbolFamily

        KEYWORDS = Set{
          "abstract", "alias", "annotation", "as", "asm", "begin", "break",
          "case", "class", "def", "do", "else", "elsif", "end", "ensure",
          "enum", "extend", "false", "for", "fun", "if", "in", "include",
          "instance_sizeof", "is_a?", "lib", "macro", "module", "next", "nil",
          "nil?", "of", "offsetof", "out", "pointerof", "private", "protected",
          "require", "rescue", "responds_to?", "return", "select", "self",
          "sizeof", "struct", "super", "then", "true", "type", "typeof",
          "uninitialized", "union", "unless", "until", "verbatim", "when",
          "while", "with", "yield",
        }

        def self.prepare(snapshot : Compiler::Snapshot, path : String, offset : Int32) : Preparation?
          index = snapshot.editor_index
          symbol = index.symbol_at(path, offset)
          return unless symbol
          family = index.symbol_family(symbol)
          return unless family && supported?(family) && !family.declaration_ranges.empty?
          return unless valid_name?(family, family.name)

          occurrence = index.reference_at(path, offset).try(&.range) ||
                       index.declaration_at(path, offset).try(&.range)
          return unless occurrence
          Preparation.new(occurrence, family.name, family)
        end

        def self.plan(snapshot : Compiler::Snapshot, path : String, offset : Int32, new_name : String) : Plan?
          preparation = prepare(snapshot, path, offset)
          return unless preparation
          family = preparation.family
          return if new_name == family.name || !valid_name?(family, new_name)
          return if collision?(snapshot.editor_index, family, new_name)

          ranges = ranges(snapshot.editor_index, family)

          edits = ranges.uniq.compact_map do |range|
            file = snapshot.source.file?(range.path)
            next unless file
            spelling = file.code.byte_slice(range.start_offset, range.length)
            replacement = replacement_for(spelling, family.name, new_name)
            return unless replacement
            Edit.new(range, replacement)
          end
          edits.sort_by! { |edit| {edit.range.path, edit.range.start_offset, edit.range.end_offset} }
          return if overlapping?(edits)
          Plan.new(edits, family)
        end

        def self.ranges(index : Index, family : Index::SymbolFamily) : Array(Source::Range)
          ranges = family.declaration_ranges.dup
          family.symbols.each do |symbol|
            index.occurrences(symbol, include_declaration: false).each { |range| ranges << range }
          end
          ranges.uniq.sort_by { |range| {range.path, range.start_offset, range.end_offset} }
        end

        private def self.collision?(index : Index, family : Index::SymbolFamily, new_name : String) : Bool
          index.rename_collision?(family, new_name)
        end

        private def self.replacement_for(spelling : String, old_name : String, new_name : String) : String?
          return new_name if spelling == old_name
          return "@#{new_name}" if spelling == "@#{old_name}"
          nil
        end

        private def self.overlapping?(edits : Array(Edit)) : Bool
          edits.each_cons_pair.any? do |left, right|
            left.range.path == right.range.path && left.range.end_offset > right.range.start_offset
          end
        end

        private def self.valid_name?(family : Index::SymbolFamily, name : String) : Bool
          return false if KEYWORDS.includes?(name)
          if family.symbols.any?(&.kind.class?)
            !!name.match(/\A[A-Z][A-Za-z0-9_]*\z/)
          else
            !!name.match(/\A[a-z_][A-Za-z0-9_]*\z/)
          end
        end

        private def self.supported?(family : Index::SymbolFamily) : Bool
          return true if family.kind.callable? || family.kind.accessor?
          family.kind.single? && family.symbols.all? do |symbol|
            symbol.kind.local? || symbol.kind.parameter? ||
              symbol.kind.block_argument? || symbol.kind.block_parameter?
          end
        end
      end
    end
  end
end
