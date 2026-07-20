module Tango
  module Analysis
    module Passes
      # Records semantic type relationships. Crystal already inferred and
      # narrowed the types; this pass only names the relationship planning will
      # use when selecting a carrier-tag, pointer, or static strategy.
      class CoreDispatch
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          program.body.each { |node| visit(node, table) }
        end

        private def visit(node : IR::NIR::Stmt, table : Facts::Table) : Nil
          case node
          when IR::NIR::TypeTest, IR::NIR::Cast
            source = node.value.type || IR::Type.unknown
            table.dispatch_relations[node.id] = Facts::DispatchRelation.new(source, node.target, relation(source, node.target))
          end
          IR::NIR::Walk.non_binding_children(node).each { |child| visit(child, table) }
        end

        private def relation(source : IR::Type, target : IR::Type) : Facts::TypeRelation
          return Facts::TypeRelation::Exact if source == target
          return Facts::TypeRelation::Member if source.union? && source.members.includes?(target)
          return Facts::TypeRelation::Widening if target.union? && target.members.includes?(source)
          Facts::TypeRelation::Impossible
        end
      end
    end
  end
end
