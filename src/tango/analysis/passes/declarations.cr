module Tango
  module Analysis
    module Passes
      # Records source declaration ownership before references and planning run.
      # Paths remain segmented throughout; this pass never manufactures or
      # interprets a target-language identifier.
      class Declarations
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          IR::NIR::Walk.children(program).each { |node| visit(node, table) }
        end

        private def visit(node : IR::NIR::Stmt, table : Facts::Table) : Nil
          case node
          when IR::NIR::Namespace
            parent = node.path.size > 1 ? node.path[0...-1] : nil
            table.namespaces[node.id] = Facts::NamespaceDefinition.new(node.path, parent)
          when IR::NIR::Constant
            table.constants[node.path] = Facts::ConstantDefinition.new(node.id, node.path, node.type)
          when IR::NIR::TypeAlias
            table.type_aliases[node.path] = Facts::TypeAliasDefinition.new(node.id, node.path, node.target)
          when IR::NIR::Def
            table.namespace_owners[node.id] = node.namespace_path unless node.namespace_path.empty?
          end

          IR::NIR::Walk.children(node).each { |child| visit(child, table) }
        end
      end
    end
  end
end
