module Tango
  module Lowering
    # Channel/select lowering, mixed into ToLIR. Send/close/receive channel ops
    # in statement and value position, plus the multi-way select.
    module ConcurrencyLowering
      # Send and close are statements; a receive used for effect evaluates and
      # discards. The receive value path holds the checked-helper shape.
      private def lower_channel_op_stmt(stmt : IR::NIR::ChannelOp, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Stmt
        channel = lower_value(stmt.channel, facts, plans)
        case stmt.kind
        in .send?
          value = stmt.value
          return IR::LIR::UnsupportedStmt.new("channel send without a value", loc(stmt.span)) unless value
          IR::LIR::ChanSend.new(channel, lower_operand(value, stmt.element, facts, plans), loc(stmt.span))
        in .close?
          IR::LIR::ChanClose.new(channel, loc(stmt.span))
        in .receive?, .receive_maybe?, .next_state?
          IR::LIR::Discard.new(lower_channel_op_value(stmt, facts, plans), loc(stmt.span))
        end
      end

      # Each arm becomes one comm clause. Binding-use is an analysis fact query:
      # an unread source binding commits to nil here so the target emits `_`.
      # receive? representation is read from planning and committed as a pointer
      # or carrier arm; the target never re-derives that choice.
      private def lower_select(stmt : IR::NIR::Select, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Stmt
        arms = [] of IR::LIR::Select::Arm
        stmt.arms.each do |arm|
          channel = lower_value(arm.channel, facts, plans)
          binding = arm.captured.try { |captured| facts.binding_used?(captured.id) ? captured.name : nil }
          context = @context.child
          arm.captured.try { |captured| context.declare(captured.name, captured.type) }
          body = with_lowering_context(context) { lower_block(arm.body, facts, plans) }
          case arm.kind
          in .receive?
            arms << IR::LIR::Select::Arm.new(IR::LIR::Select::Arm::Kind::Receive, channel, nil, binding, arm.element, body)
          in .send?
            value = arm.value
            return IR::LIR::UnsupportedStmt.new("select send arm without a value", loc(stmt.span)) unless value
            arms << IR::LIR::Select::Arm.new(IR::LIR::Select::Arm::Kind::Send, channel, lower_value(value, facts, plans), nil, arm.element, body)
          in .receive_maybe?
            result_type = arm.captured.try(&.type) || arm.element.with_nil
            case plans.reprs[result_type]?
            when Planning::Plans::PointerRepr
              arms << IR::LIR::Select::Arm.new(IR::LIR::Select::Arm::Kind::ReceiveMaybePointer, channel, nil, binding, arm.element, body, result_type)
            when Planning::Plans::CarrierRepr
              arms << IR::LIR::Select::Arm.new(IR::LIR::Select::Arm::Kind::ReceiveMaybeCarrier, channel, nil, binding, arm.element, body, result_type)
            else
              return IR::LIR::UnsupportedStmt.new("unplanned select receive? representation", loc(stmt.span))
            end
          in .next_state?
            return IR::LIR::UnsupportedStmt.new("channel next-state is not a select operation", loc(stmt.span))
          in .close?
            return IR::LIR::UnsupportedStmt.new("select close arm is not lowered", loc(stmt.span))
          end
        end
        default = stmt.else_body.try { |body| lower_block(body, facts, plans) }
        IR::LIR::Select.new(arms, default, loc(stmt.span))
      end

      private def lower_channel_op_value(stmt : IR::NIR::ChannelOp, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        channel = lower_value(stmt.channel, facts, plans)
        case stmt.kind
        in .receive?
          IR::LIR::ChanReceive.new(channel, stmt.element)
        in .receive_maybe?
          # `T?` rides whichever arm the union plan already committed for this
          # receive's result type: a `PointerRepr` reference element is the raw
          # `<-ch` pointer (nil == closed); a `CarrierRepr` value element needs
          # comma-ok + a carrier box — a distinct statement shape deferred until
          # an example forces it.
          type = stmt.type
          return IR::LIR::UnsupportedValue.new("receive? has no resolved result type", loc(stmt.span)) unless type
          case plans.reprs[type]?
          when Planning::Plans::PointerRepr
            IR::LIR::ChanReceiveMaybe.new(channel, stmt.element)
          when Planning::Plans::CarrierRepr
            IR::LIR::ChanReceiveMaybeBox.new(channel, stmt.element, type)
          else
            IR::LIR::UnsupportedValue.new("unplanned receive? representation", loc(stmt.span))
          end
        in .next_state?
          type = stmt.type
          return IR::LIR::UnsupportedValue.new("channel next-state has no resolved result type", loc(stmt.span)) unless type
          IR::LIR::ChanReceiveState.new(channel, stmt.element, type, "value", "open")
        in .send?, .close?
          IR::LIR::UnsupportedValue.new("unsupported channel op #{stmt.kind} in value position", loc(stmt.span))
        end
      end
    end
  end
end
