module Tango
  module Lowering
    # Exception-handler lowering, mixed into ToLIR. Covers both the statement
    # handler and the value handler (rescue-as-expression), and the shared
    # binding-liveness and catch-all/no-return predicates they depend on.
    module ExceptionLowering
      # A rescue clause catches everything when it names no type (bare `rescue`)
      # or names the root `Exception` — either way the target emits its arm with
      # no runtime `tangoIsA` check. Deciding it here, once, keeps the catch-all
      # determination single-sourced on the committed LIR clause instead of
      # re-derived by name at the target.
      private def rescue_catch_all?(types : Array(IR::Type)) : Bool
        types.empty? || types.any?(&.exception_root?)
      end

      private def lower_handler(stmt : IR::NIR::ExceptionHandler, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Stmt
        plan = plans.handlers[stmt.id]?
        return IR::LIR::UnsupportedStmt.new("unplanned exception handler", loc(stmt.span)) unless plan && plan.strategy.recover_dispatch?

        clauses = stmt.clauses.map do |clause|
          binding = clause.binding
          name = binding && facts.binding_used?(binding.id) ? binding.name : nil
          IR::LIR::RescueClause(Array(IR::LIR::Stmt)).new(clause.types, name, lower_block(clause.body, facts, plans), rescue_catch_all?(clause.types))
        end
        IR::LIR::Handler.new(
          lower_block(stmt.body, facts, plans),
          clauses,
          stmt.else_branch.try { |branch| lower_block(branch, facts, plans) },
          stmt.ensure_branch.try { |branch| lower_block(branch, facts, plans) },
          no_return?(stmt.type),
          loc(stmt.span)
        )
      end

      private def lower_handler_value(stmt : IR::NIR::ExceptionHandler, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        plan = plans.handlers[stmt.id]?
        return IR::LIR::UnsupportedValue.new("unplanned value exception handler", loc(stmt.span)) unless plan && plan.strategy.recover_dispatch?

        type = stmt.type || IR::Type.unknown
        clauses = stmt.clauses.map do |clause|
          binding = clause.binding
          name = binding && facts.binding_used?(binding.id) ? binding.name : nil
          IR::LIR::RescueClause(IR::LIR::RescueValue::Arm).new(clause.types, name, lower_handler_arm(clause.body, type, facts, plans), rescue_catch_all?(clause.types))
        end

        else_arm = stmt.else_branch.try { |branch| lower_handler_arm(branch, type, facts, plans) }
        body = if else_arm
                 # Crystal discards the protected body's value when an else arm
                 # exists; only the else arm fills the result slot.
                 IR::LIR::RescueValue::Arm.new(lower_block(stmt.body, facts, plans), nil)
               else
                 lower_handler_arm(stmt.body, type, facts, plans)
               end

        IR::LIR::RescueValue.new(
          body,
          clauses,
          else_arm,
          stmt.ensure_branch.try { |branch| lower_block(branch, facts, plans) },
          type
        )
      end

      private def lower_handler_arm(block : IR::NIR::Block, type : IR::Type, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::RescueValue::Arm
        stmts = block.body
        last = stmts.last?
        if last.is_a?(IR::NIR::Expr) && !no_return?(last.type)
          body = stmts[0...-1].map { |stmt| lower_stmt(stmt, facts, plans) }
          IR::LIR::RescueValue::Arm.new(body, lower_operand(last, type, facts, plans))
        else
          IR::LIR::RescueValue::Arm.new(stmts.map { |stmt| lower_stmt(stmt, facts, plans) }, nil)
        end
      end

      private def no_return?(type : IR::Type?) : Bool
        type.try(&.no_return?) || false
      end
    end
  end
end
