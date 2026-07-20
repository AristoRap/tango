module Tango
  module Planning
    module Strategies
      class Calls
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          program.body.each { |stmt| visit(stmt, facts, table) }
        end

        private def visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          case node
          when IR::NIR::Call, IR::NIR::SemanticOperation
            call = node.is_a?(IR::NIR::Call) ? node : node.fallback
            unless call.primitive
              table.calls[node.id] =
                if resolved = facts.internal_calls[node.id]?
                  table.monomorphs[resolved.definition]?.try do |definition|
                    Plans::InternalCall.new(definition.name)
                  end || Plans::UnsupportedCall.new
                elsif callee = facts.go_externals[node.id]?.try(&.first?)
                  Plans::ExternalGo.new(callee)
                else
                  Plans::UnsupportedCall.new
                end
            end
          end

          IR::NIR::Walk.non_binding_children(node).each { |child| visit(child, facts, table) }
        end
      end
    end
  end
end
