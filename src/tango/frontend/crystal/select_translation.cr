module Tango
  module Frontend
    module Crystal
      # Reconstructs Crystal's expanded `select` statement window as one NIR
      # node. The expansion-specific pattern matching stays separate from the
      # general typed-AST dispatcher in ToNIR.
      module SelectTranslation
        private record SelectAction,
          call : ::Crystal::Call,
          kind : IR::NIR::ChannelOp::Kind,
          receiver : ::Crystal::ASTNode

        # A statement list, recognizing the `select` anchor window (which spans
        # the `__temp = Channel.select(...)` assign, two tuple-index binds, and the
        # if-chain) and folding it into one `Select` node. Everything else
        # translates one node at a time.
        private def translate_statements(nodes : Array(::Crystal::ASTNode)) : Array(IR::NIR::Stmt)
          stmts = [] of IR::NIR::Stmt
          index = 0
          while index < nodes.size
            if selected = try_translate_select(nodes, index)
              node, consumed = selected
              stmts << node
              index += consumed
            else
              stmts << translate_stmt(nodes[index])
              index += 1
            end
          end
          stmts
        end

        # Recognizes the `select` expansion at `nodes[start]` — the anchor assign
        # `__tuple = Channel.select({ch.receive_select_action, ...})`, the two
        # `__tuple[0]`/`__tuple[1]` index binds, and the if-chain over the index —
        # and folds it into one `Select` node. Returns the node and the count of
        # statements it consumed, or nil when the window is not a select.
        private def try_translate_select(nodes : Array(::Crystal::ASTNode), start : Int32) : {IR::NIR::Select, Int32}?
          anchor = nodes[start]?
          return nil unless anchor.is_a?(::Crystal::Assign)
          tuple_target = anchor.target
          return nil unless tuple_target.is_a?(::Crystal::Var) && tuple_target.name.starts_with?("__temp_")
          call = anchor.value
          return nil unless call.is_a?(::Crystal::Call) && call.name.in?("select", "non_blocking_select")
          tuple = call.args.first?
          return nil unless tuple.is_a?(::Crystal::TupleLiteral)

          actions = [] of SelectAction
          tuple.elements.each do |element|
            return nil unless element.is_a?(::Crystal::Call)
            kind = select_action_kind(element.name)
            receiver = element.obj
            return nil unless kind && receiver
            return nil unless valid_select_action_arity?(element, kind)
            actions << SelectAction.new(element, kind, receiver)
          end

          index_name = select_index_binding(nodes[start + 1]?, tuple_target.name, 0)
          value_name = select_index_binding(nodes[start + 2]?, tuple_target.name, 1)
          return nil unless index_name && value_name

          if_chain = nodes[start + 3]?
          return nil unless if_chain.is_a?(::Crystal::If)

          split = select_arm_bodies(if_chain, index_name, actions.size, blocking: call.name == "select")
          return nil unless split
          bodies, else_node = split

          arms = actions.map_with_index { |action, i| build_select_arm(action, bodies[i], value_name) }
          else_body = else_node.try { |node| translate_block(node) }
          {IR::NIR::Select.new(next_id, arms, else_body, IR::Type::NIL, span(anchor)), 4}
        end

        private def select_action_kind(name : String) : IR::NIR::ChannelOp::Kind?
          case name
          when "receive_select_action"  then IR::NIR::ChannelOp::Kind::Receive
          when "receive_select_action?" then IR::NIR::ChannelOp::Kind::ReceiveMaybe
          when "send_select_action"     then IR::NIR::ChannelOp::Kind::Send
          end
        end

        private def valid_select_action_arity?(call : ::Crystal::Call, kind : IR::NIR::ChannelOp::Kind) : Bool
          kind.send? ? call.args.size == 1 : call.args.empty?
        end

        # `<var> = <tuple_name>[<idx>]` — a tuple-index bind; returns the bound
        # var's name (the index or value temp).
        private def select_index_binding(node : ::Crystal::ASTNode?, tuple_name : String, idx : Int32) : String?
          return nil unless node.is_a?(::Crystal::Assign)
          target = node.target
          return nil unless target.is_a?(::Crystal::Var)
          call = node.value
          return nil unless call.is_a?(::Crystal::Call) && call.name == "[]"
          obj = call.obj
          return nil unless obj.is_a?(::Crystal::Var) && obj.name == tuple_name
          arg = call.args.first?
          return nil unless arg.is_a?(::Crystal::NumberLiteral) && arg.value == idx.to_s
          target.name
        end

        # Walks exactly `arms` `If`s of the index dispatch chain, collecting each
        # arm's body. The else after the last `If` is the `raise "BUG"` sentinel
        # when blocking (discarded) or the real `else` body when non-blocking.
        private def select_arm_bodies(if_chain : ::Crystal::If, index_name : String, arms : Int32, blocking : Bool) : {Array(::Crystal::ASTNode), ::Crystal::ASTNode?}?
          bodies = [] of ::Crystal::ASTNode
          node = if_chain.as(::Crystal::ASTNode)
          arms.times do |index|
            return nil unless node.is_a?(::Crystal::If)
            return nil unless select_index_condition?(node.cond, index_name, index)
            bodies << node.then
            node = node.else
          end
          return nil if blocking && !select_bug_sentinel?(node)
          {bodies, blocking ? nil : node}
        end

        private def select_index_condition?(node : ::Crystal::ASTNode, index_name : String, index : Int32) : Bool
          return false unless node.is_a?(::Crystal::Call) && node.name == "===" && node.args.size == 1
          receiver = node.obj
          value = node.args.first
          receiver.is_a?(::Crystal::NumberLiteral) && receiver.value == index.to_s &&
            value.is_a?(::Crystal::Var) && value.name == index_name
        end

        private def select_bug_sentinel?(node : ::Crystal::ASTNode) : Bool
          node = node.expressions.first if node.is_a?(::Crystal::Expressions) && node.expressions.size == 1
          return false unless node.is_a?(::Crystal::Call) && node.name == "raise" && node.global? && node.args.size == 1
          message = node.args.first
          message.is_a?(::Crystal::StringLiteral) && message.value.starts_with?("BUG")
        end

        private def build_select_arm(action : SelectAction, body_node : ::Crystal::ASTNode, value_name : String) : IR::NIR::Select::Arm
          channel = translate_expr(action.receiver)
          element = channel_element(type_of(action.receiver))
          value = action.kind.send? ? action.call.args.first?.try { |arg| translate_expr(arg) } : nil
          captured_type = action.kind.receive_maybe? ? element.with_nil : element
          captured, body = split_captured_receive(body_node, value_name, captured_type)
          operation = IR::NIR::ChannelOp.new(
            next_id,
            action.kind,
            channel,
            value,
            element,
            select_operation_type(action.kind, element),
            span(action.call),
            select_method_site(action, channel, value, element)
          )
          IR::NIR::Select::Arm.new(operation, captured, body)
        end

        private def select_operation_type(kind : IR::NIR::ChannelOp::Kind, element : IR::Type) : IR::Type
          case kind
          when .receive?       then element
          when .receive_maybe? then element.with_nil
          else                      IR::Type::NIL
          end
        end

        private def select_method_site(action : SelectAction, channel : IR::NIR::Expr, value : IR::NIR::Expr?, element : IR::Type) : IR::NIR::MethodSite
          name = case action.kind
                 when .send?          then "send"
                 when .receive?       then "receive"
                 when .receive_maybe? then "receive?"
                 else                      action.call.name
                 end
          argument_types = value.try { |argument| [argument.type || IR::Type.unknown] } || [] of IR::Type
          IR::NIR::MethodSite.new(
            channel.type || IR::Type.unknown,
            name,
            argument_types,
            select_operation_type(action.kind, element),
            name_span(action.call.name_location, name),
            IR::NIR::CallableKind::InstanceMethod
          )
        end

        # A receive-assign arm's body opens with `x = <value_temp>.as(...)`; lift
        # `x` to the arm's bound local (typed as the element) and drop that assign,
        # leaving the user's own body. A bare-receive/send arm has no such prefix.
        private def split_captured_receive(body_node : ::Crystal::ASTNode, value_name : String, element : IR::Type) : {IR::NIR::Local?, IR::NIR::Block}
          stmts = body_node.is_a?(::Crystal::Expressions) ? body_node.expressions : [body_node]
          first = stmts.first?
          if first.is_a?(::Crystal::Assign)
            target = first.target
            value = first.value
            if target.is_a?(::Crystal::Var) && value.is_a?(::Crystal::Cast) && (obj = value.obj).is_a?(::Crystal::Var) && obj.name == value_name
              captured = IR::NIR::Local.new(next_id, target.name, element, span(target), name_span: name_span(target.location, target.name))
              rest = translate_statements(stmts[1..].reject(::Crystal::Nop))
              return {captured, IR::NIR::Block.new(next_id, rest, span(body_node))}
            end
          end
          {nil, translate_block(body_node)}
        end
      end
    end
  end
end
