module Tango
  module Compiler
    module Editor
      # Protocol-neutral hover query. The result stays structured through the
      # compiler boundary; the LSP (or another client) owns presentation.
      module Hover
        abstract struct Subject
        end

        record ClassSubject < Subject, name : String
        record StructSubject < Subject, name : String
        record EnumSubject < Subject, name : String
        record EnumMemberSubject < Subject, owner : IR::Type, name : String
        record ConstantSubject < Subject, name : String, type : IR::Type
        record TypeAliasSubject < Subject, name : String, target : IR::Type
        record BindingSubject < Subject, name : String, type : IR::Type, kind : Index::SymbolKind
        record CallableSubject < Subject,
          owner : IR::Type?,
          name : String,
          parameters : Array(Index::Parameter),
          return_type : IR::Type?,
          kind : IR::NIR::CallableKind do
          def parameter_types : Array(IR::Type)
            parameters.map(&.type)
          end
        end
        record ProcSubject < Subject, name : String, parameter_types : Array(IR::Type), return_type : IR::Type?

        enum Note
          CapturedByGoroutine
        end

        record Result,
          subject : Subject,
          range : Source::Range,
          symbol : Index::SymbolId? = nil,
          notes : Array(Note) = [] of Note,
          documentation : String? = nil

        def self.at(snapshot : Snapshot, path : String, line : Int32, column : Int32) : Result?
          file = snapshot.source.files.find { |candidate| candidate.path == path }
          return nil unless file

          offset = file.line_index.byte_offset_at(line, column)
          index = snapshot.editor_index

          if reference = index.reference_at(path, offset)
            declaration = reference.declaration.try { |id| index.declaration(id) }

            semantic = index.semantic_node(reference.node)
            if site = semantic.try(&.method_site)
              # A single expression can contain several semantic occurrences.
              # Only the callee token uses call-site signature data; receiver
              # tokens keep their own declarations (`Point` vs `new`).
              if site.name_span == reference.range
                parameters = site.argument_types.map_with_index do |type, index|
                  name = declaration.try(&.signature).try { |signature| signature.parameters[index]?.try(&.name) } || ""
                  Index::Parameter.new(name, type)
                end
                return Result.new(
                  CallableSubject.new(site.owner, site.name, parameters, site.return_type, site.kind),
                  reference.range,
                  reference.declaration,
                  documentation: declaration.try(&.documentation)
                )
              end
            end

            if declaration
              return from_declaration(declaration, index, semantic.try(&.type), reference.range)
            end
          end

          if declaration = index.declaration_at(path, offset)
            return from_declaration(declaration, index)
          end

          nil
        end

        private def self.from_declaration(
          declaration : Index::Declaration,
          index : Index,
          occurrence_type : IR::Type? = nil,
          occurrence_range : Source::Range? = nil,
        ) : Result?
          subject : Subject = case declaration.kind
          when .class?
            ClassSubject.new(declaration.name)
          when .struct?
            StructSubject.new(declaration.name)
          when .enum?
            EnumSubject.new(declaration.name)
          when .enum_member?
            type = declaration.type
            return nil unless type
            EnumMemberSubject.new(type, declaration.name)
          when .constant?
            type = declaration.type
            return nil unless type
            ConstantSubject.new(declaration.name, type)
          when .type_alias?
            target = declaration.type
            return nil unless target
            TypeAliasSubject.new(declaration.name, target)
          when .function?, .method?, .constructor?
            signature = declaration.signature
            return nil unless signature
            CallableSubject.new(signature.owner, declaration.name, signature.parameters, signature.return_type, signature.kind)
          when .block_parameter?
            signature = declaration.signature
            return nil unless signature
            ProcSubject.new(declaration.name, signature.parameters.map(&.type), signature.return_type)
          else
            # A symbol has one declaration identity but each use can have a
            # flow-narrowed type. Hover the occurrence's type while keeping
            # declaration-owned navigation and capture metadata.
            type = occurrence_type || declaration.type
            return nil unless type
            BindingSubject.new(declaration.name, type, declaration.kind)
          end

          notes = [] of Note
          if index.captured?(declaration.id)
            notes << Note::CapturedByGoroutine
          end
          Result.new(subject, occurrence_range || declaration.range, declaration.id, notes, declaration.documentation)
        end
      end
    end
  end
end
