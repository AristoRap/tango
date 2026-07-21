module Tango
  module Compiler
    module Editor
      # Protocol-neutral navigation from an expression or binding to the source
      # declaration of its resolved type. The exact contract is intentionally
      # narrow: one concrete user-declared class produces one target; unions,
      # built-ins, and unknown types produce no result instead of a partial list.
      module TypeDefinition
        enum Completeness
          Exact
        end

        record Result,
          type : IR::Type,
          target : Source::Range,
          completeness : Completeness

        def self.at(snapshot : Snapshot, path : String, line : Int32, column : Int32) : Result?
          file = snapshot.source.file?(path)
          return nil unless file

          offset = file.line_index.byte_offset_at(line, column)
          index = snapshot.editor_index
          type = type_at(index, path, offset)
          return nil unless type && type.family.class?
          declaration = index.class_declaration(type)
          return nil unless declaration

          Result.new(type, declaration.range, Completeness::Exact)
        end

        private def self.type_at(index : Index, path : String, offset : Int32) : IR::Type?
          if reference = index.reference_at(path, offset)
            semantic_type = index.semantic_node(reference.node).try(&.type)
            return semantic_type if semantic_type
            return reference.declaration.try { |id| declaration_type(index.declaration(id)) }
          end

          declaration_type(index.declaration_at(path, offset))
        end

        private def self.declaration_type(declaration : Index::Declaration?) : IR::Type?
          return nil unless declaration
          return IR::Type.klass(declaration.name) if declaration.kind.class? || declaration.kind.struct?
          declaration.type || declaration.signature.try(&.return_type)
        end
      end
    end
  end
end
