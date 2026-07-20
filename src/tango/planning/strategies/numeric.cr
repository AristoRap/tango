module Tango
  module Planning
    module Strategies
      class Numeric
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          program.body.each { |node| visit(node, facts, table) }
        end

        private def visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          if node.is_a?(IR::NIR::Call) && checked?(node)
            type = facts.types.expressions[node.id]?
            if type && (width = type.width)
              strategy = if width.bits < 64
                           IR::CheckedArithmeticStrategy::WideningRoundTrip
                         elsif width.signed?
                           IR::CheckedArithmeticStrategy::SignedSameWidth
                         else
                           IR::CheckedArithmeticStrategy::UnsignedSameWidth
                         end
              table.checked_arithmetic[node.id] = Plans::CheckedArithmeticPlan.new(strategy)
            end
          end

          IR::NIR::Walk.non_binding_children(node).each { |child| visit(child, facts, table) }
        end

        private def checked?(node : IR::NIR::Call) : Bool
          node.primitive.try do |primitive|
            primitive.kind.checked_add? || primitive.kind.checked_sub? || primitive.kind.checked_mul?
          end || false
        end
      end
    end
  end
end
