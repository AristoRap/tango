module Tango
  module Target
    module Go
      class FromLIR
        # A value handler uses the statement handler's real frame, but each
        # falling arm fills one typed result slot. Keeping the frame real (not
        # wrapping the whole construct in a value-returning IIFE) is what lets
        # return/break/next replay outside it through translate_abrupt_exit.
        private def translate_rescue_value_assign(target : String, mode : Tango::IR::LIR::Assign::Mode, value : Tango::IR::LIR::RescueValue, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          result = [] of IR::Stmt
          result << IR::VarDecl.new(target, go_type(value.type)) if mode.declare?
          result.concat(translate_rescue_value_protocol(value, target, requirements))
          result
        end

        private def translate_rescue_value_return(value : Tango::IR::LIR::RescueValue, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          slot = @names.temp("result")
          result = [IR::VarDecl.new(slot, go_type(value.type)).as(IR::Stmt)]
          result.concat(translate_rescue_value_protocol(value, slot, requirements))
          # The slot's normal fallthrough is still a language return. Route it
          # through the same chokepoint so an enclosing handler can intercept
          # it; emitting a raw Go return here would let nested value handlers
          # bypass outer abrupt-flow replay.
          result.concat(translate_abrupt_exit(
            Tango::IR::LIR::AbruptExit.new(Tango::IR::LIR::AbruptExit::Shape::Return, Tango::IR::LIR::Temp.new(slot)),
            requirements
          ))
          result
        end

        private def translate_rescue_value_protocol(value : Tango::IR::LIR::RescueValue, slot : String, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          context = HandlerContext.new(@names.temp("handler"))
          ensure_body, clause_bodies, protected_body, else_body = @function.with_handler(context) do
            {
              value.ensure_body.try { |body| translate_body(body, requirements) },
              value.clauses.map { |clause| {clause, translate_rescue_arm(clause.body, slot, requirements)} },
              translate_rescue_arm(value.body, slot, requirements),
              value.else_arm.try { |arm| translate_rescue_arm(arm, slot, requirements) },
            }
          end

          assemble_handler(context, ensure_body, clause_bodies, protected_body, else_body, requirements)
        end

        # The shared handler frame both handler forms emit: an ensure defer, a
        # recover defer, the protected body and optional else inside an IIFE, the
        # outer signal/payload vars, and the abrupt-exit replay. The statement
        # form (translate_handler) and value form (translate_rescue_value_protocol)
        # differ only in how they translate the four bodies and what tail they
        # append after this — so the frame lives here once and both route through it.
        private def assemble_handler(context : HandlerContext, ensure_body : Array(IR::Stmt)?, clause_bodies : Array(Tuple(C, Array(IR::Stmt))), protected_body : Array(IR::Stmt), else_body : Array(IR::Stmt)?, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt) forall C
          closure = [] of IR::Stmt
          if body = ensure_body
            closure << IR::DeferStmt.new(IR::Call.new(IR::FuncLit.new([] of IR::Param, nil, body), [] of IR::Expr))
          end

          done = nil.as(String?)
          unless clause_bodies.empty?
            if else_body
              done = @names.temp("done")
              closure << IR::AssignStmt.new(IR::Ident.new(done), IR::AssignStmt::Mode::Declare, IR::BoolLit.new(false))
            end
            recover = translate_recover(clause_bodies, done, requirements)
            closure << IR::DeferStmt.new(IR::Call.new(IR::FuncLit.new([] of IR::Param, nil, recover), [] of IR::Expr))
          end

          closure.concat(protected_body)
          if body = else_body
            done.try { |name| closure << IR::AssignStmt.new(IR::Ident.new(name), IR::AssignStmt::Mode::Reassign, IR::BoolLit.new(true)) }
            closure.concat(body)
          end

          result = [] of IR::Stmt
          unless context.tags.empty?
            result << IR::VarDecl.new(context.signal, "uint8")
            context.payload.try { |payload| result << IR::VarDecl.new(payload, go_type(@function.return_type)) }
          end
          result << IR::ExprStmt.new(IR::Call.new(IR::FuncLit.new([] of IR::Param, nil, closure), [] of IR::Expr))
          result.concat(replay_handler_exits(context, requirements))
          result
        end

        private def translate_rescue_arm(arm : Tango::IR::LIR::RescueValue::Arm, slot : String, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          body = translate_body(arm.body, requirements)
          arm.value.try do |value|
            if nested = value.as?(Tango::IR::LIR::RescueValue)
              body.concat(translate_rescue_value_protocol(nested, slot, requirements))
            else
              body << IR::AssignStmt.new(IR::Ident.new(slot), IR::AssignStmt::Mode::Reassign, translate_value(value, requirements))
            end
          end
          body
        end

        private def replay_handler_exits(context : HandlerContext, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          result = [] of IR::Stmt
          context.tags.each do |shape, tag|
            value = if shape.return?
                      context.payload.try { |payload| Tango::IR::LIR::Temp.new(payload).as(Tango::IR::LIR::Value) }
                    end
            replay = Tango::IR::LIR::AbruptExit.new(shape, value, target: context.targets[shape]?)
            result << IR::IfStmt.new(
              IR::Binary.new(IR::Ident.new(context.signal), "==", IR::IntLit.new(tag.to_s)),
              translate_abrupt_exit(replay, requirements),
              [] of IR::Stmt
            )
          end
          result
        end
      end
    end
  end
end
