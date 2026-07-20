module Tango
  module Frontend
    module Crystal
      # Required Tango files contribute declarations, never executable top-level
      # work. Check Crystal's expanded tree so declaration-producing macros are
      # judged by what they produce rather than by their surface call shape.
      module RequiredFileCheck
        def self.run(node : ::Crystal::ASTNode, source : Source::CompilationUnit) : Array(Diagnostic)
          entrypoint = source.entrypoint.path
          top_level_nodes(node).compact_map do |child|
            location = child.location
            next unless location
            filename = location.filename
            next unless filename.is_a?(String) && filename != entrypoint
            file = source.file?(filename)
            next unless file
            next if declaration?(child)

            range = file.token_range_at(location.line_number, location.column_number)
            Diagnostic.new(
              Diagnostic::Origin::Frontend,
              Diagnostic::Severity::Error,
              Diagnostics::FRONT_REQUIRE_TOP_LEVEL,
              "a required file is definitions-only; executable top-level statements belong in #{entrypoint}",
              file: file.path,
              line: range.line || location.line_number,
              column: range.column || location.column_number,
              size: range.length,
              range: range
            )
          end
        end

        private def self.top_level_nodes(node : ::Crystal::ASTNode) : Array(::Crystal::ASTNode)
          case node
          when ::Crystal::Expressions
            node.expressions.flat_map { |child| top_level_nodes(child) }
          when ::Crystal::Nop
            [] of ::Crystal::ASTNode
          else
            [node] of ::Crystal::ASTNode
          end
        end

        private def self.declaration?(node : ::Crystal::ASTNode) : Bool
          case node
          when ::Crystal::Def,
               ::Crystal::ClassDef,
               ::Crystal::ModuleDef,
               ::Crystal::Annotation,
               ::Crystal::AnnotationDef,
               ::Crystal::LibDef,
               ::Crystal::TypeDef,
               ::Crystal::CStructOrUnionDef,
               ::Crystal::EnumDef,
               ::Crystal::Alias,
               ::Crystal::Macro,
               ::Crystal::Include,
               ::Crystal::Extend
            true
          when ::Crystal::Assign
            node.target.is_a?(::Crystal::Path)
          else
            false
          end
        end
      end
    end
  end
end
