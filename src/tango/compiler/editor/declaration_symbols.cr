module Tango
  module Compiler
    module Editor
      class Index
        private def add_class(stmt : IR::NIR::Class) : Nil
          range = declaration_range(stmt)
          return unless range
          kind = stmt.reference? ? SymbolKind::Class : SymbolKind::Struct
          class_id = SymbolId.new(stmt.id, kind)
          add_declaration(Declaration.new(class_id, stmt.name, range))
          stmt.fields.each do |field|
            field_range = stmt.initializers.find { |initializer| initializer.name == field.name }.try(&.name_span) || range
            add_declaration(
              Declaration.new(SymbolId.new(stmt.id, SymbolKind::Field, field.name), field.name, field_range, field.type)
            )
          end
        end

        private def add_enum(stmt : IR::NIR::Enum) : Nil
          range = declaration_range(stmt)
          return unless range
          enum_id = SymbolId.new(stmt.id, SymbolKind::Enum)
          add_declaration(Declaration.new(enum_id, stmt.name, range, stmt.type))
          @enums_by_type[stmt.type] = enum_id
          stmt.members.each do |member|
            member_range = member.name_span || range
            add_declaration(Declaration.new(SymbolId.new(stmt.id, SymbolKind::EnumMember, member.name), member.name, member_range, stmt.type))
          end
        end

        private def add_constant(stmt : IR::NIR::Constant) : Nil
          range = declaration_range(stmt)
          add_binding(stmt.id, stmt.name, SymbolKind::Constant, stmt.type, range) if range
        end

        private def add_type_alias(stmt : IR::NIR::TypeAlias) : Nil
          range = declaration_range(stmt)
          add_binding(stmt.id, stmt.name, SymbolKind::TypeAlias, stmt.target, range) if range
        end
      end
    end
  end
end
