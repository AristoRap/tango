module Tango
  module Planning
    module Strategies
      class Exceptions
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Plans::Table) : Nil
          table.uncaught_exception = IR::UncaughtExceptionStrategy::CrystalStyle
          IR::NIR::Walk.children(program).each { |stmt| visit(stmt, table) }
        end

        private def visit(node : IR::NIR::Stmt, table : Plans::Table) : Nil
          if node.is_a?(IR::NIR::ExceptionHandler)
            table.handlers[node.id] = Plans::HandlerPlan.new(Plans::HandlerPlan::Strategy::RecoverDispatch)
          end
          IR::NIR::Walk.children(node).each { |child| visit(child, table) }
        end
      end
    end
  end
end
