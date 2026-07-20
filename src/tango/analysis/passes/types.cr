module Tango
  module Analysis
    module Passes
      class Types
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          IR::NIR::Walk.children(program).each { |stmt| visit(stmt, table) }
        end

        private def visit(node : IR::NIR::Stmt, table : Facts::Table) : Nil
          if node.is_a?(IR::NIR::Expr) && (type = node.type)
            table.types.expressions[node.id] = type
            collect_types(type, table)
          end

          IR::NIR::Walk.children(node).each { |child| visit(child, table) }
        end

        # Record every distinct union that appears, walking members so a nested
        # union contributes too. Fact collection, not strategy: the repr choice
        # is planning's.
        private def collect_types(type : IR::Type, table : Facts::Table) : Nil
          if type.union?
            table.types.unions << type
            type.members.each { |member| collect_types(member, table) }
          elsif type.array?
            table.types.arrays << type
            type.element_type.try { |element| collect_types(element, table) }
          elsif type.hash?
            table.types.hashes << type
            type.key_type.try { |key| collect_types(key, table) }
            type.value_type.try { |value| collect_types(value, table) }
          else
            type.type_args.each { |arg| collect_types(arg, table) }
          end
        end
      end
    end
  end
end
