module Tango
  module Compiler
    module Editor
      # Protocol-neutral goto-definition over the semantic editor index. Every
      # reference kind follows the same occurrence → declaration edge; query code
      # never searches NIR by names or reinterprets analysis facts.
      module Definition
        record Target, path : String, line : Int32, column : Int32, size : Int32

        def self.at(snapshot : Snapshot, path : String, line : Int32, column : Int32) : Target?
          file = snapshot.source.files.find { |candidate| candidate.path == path }
          return nil unless file

          offset = file.line_index.byte_offset_at(line, column)
          reference = snapshot.editor_index.reference_at(path, offset)
          declaration_id = reference.try(&.declaration)
          return nil unless declaration_id
          declaration = snapshot.editor_index.declaration(declaration_id)
          return nil unless declaration

          located(snapshot, declaration)
        end

        private def self.located(snapshot : Snapshot, declaration : Index::Declaration) : Target?
          range = declaration.range
          file = snapshot.source.files.find { |candidate| candidate.path == range.path }
          return nil unless file

          line, column = file.line_index.line_col(range.start_offset)
          Target.new(range.path, line, column, range.length)
        end
      end
    end
  end
end
