module Tango
  module Frontend
    module Crystal
      # Owns Crystal-resolved call normalization: public/runtime primitives,
      # receiver dispatch, internal-def discovery, and semantic annotations.
      module CallTranslation
        private def translate_call(node : ::Crystal::Call) : IR::NIR::Expr
          named_args = node.named_args
          return unsupported(node) if (named_args && !named_args.empty?) || node.block_arg

          call_targets = targets(node)

          if tango_primitive(call_targets) == "tango_raise"
            return unsupported(node) unless node.args.size == 1 && !node.block && !node.obj

            value = translate_expr(node.args.first)
            kind = value.type.try(&.family.string?) ? IR::NIR::Raise::Kind::Message : IR::NIR::Raise::Kind::Exception
            return IR::NIR::Raise.new(next_id, value, kind, type_of(node), span(node))
          end

          if receiver = node.obj
            return translate_receiver_call(node, receiver, call_targets)
          end

          translate_implicit_call(node, call_targets)
        end

        private def translate_receiver_call(node : ::Crystal::Call, receiver : ::Crystal::ASTNode, call_targets : Array(IR::NIR::CallTarget)) : IR::NIR::Expr
          if proc_call_target?(call_targets)
            return unsupported(node) if node.block

            recv = translate_expr(receiver)
            args = node.args.map { |arg| translate_expr(arg) }
            return IR::NIR::InvokeBlock.new(next_id, recv, args, type_of(node), span(node), method_site: method_site(node, recv, IR::NIR::CallableKind::Proc))
          end

          symbol = tango_primitive(call_targets)
          if symbol && (specialized = translate_receiver_primitive(node, receiver, symbol))
            return specialized
          end

          if primitive_kind = primitive_kind(call_targets)
            explicit_operand_count = primitive_kind.operand_count - 1
            return unsupported(node) unless node.args.size == explicit_operand_count && !node.block

            args = translate_receiver_call_args(node, receiver)
            primitive = IR::NIR::Primitive.new(primitive_kind, node.name)
            result_type = primitive_kind.reference_identity? ? IR::Type.bool : type_of(node)
            return IR::NIR::Call.new(next_id, node.name, args, call_targets, nil, result_type, span(node), primitive, name_span(node.name_location, node.name), method_site: explicit_method_site(node, receiver, args), dispatch_receiver: class_dispatch_receiver(receiver))
          end

          if external_target?(call_targets)
            return unsupported(node) if node.block

            args = translate_receiver_call_args(node, receiver)
            return IR::NIR::Call.new(next_id, node.name, args, call_targets, nil, type_of(node), span(node), name_span: name_span(node.name_location, node.name), method_site: explicit_method_site(node, receiver, args), dispatch_receiver: class_dispatch_receiver(receiver))
          end

          if node.name == "new" && (receiver.is_a?(::Crystal::Path) || receiver.is_a?(::Crystal::Generic))
            return translate_new(node)
          end

          queue_defs(node)
          args = translate_receiver_call_args(node, receiver)
          block = node.block.try { |inline_block| translate_block_literal(inline_block) }
          IR::NIR::Call.new(next_id, node.name, args, call_targets, block, type_of(node), span(node), name_span: name_span(node.name_location, node.name), method_site: explicit_method_site(node, receiver, args), dispatch_receiver: class_dispatch_receiver(receiver))
        end

        private def translate_receiver_primitive(node : ::Crystal::Call, receiver : ::Crystal::ASTNode, symbol : String) : IR::NIR::Expr?
          case symbol
          when "tango_interpolation"
            return unsupported(node) if node.block

            pieces = node.args.map { |arg| translate_expr(arg) }
            IR::NIR::Interpolation.new(next_id, pieces, type_of(node), span(node))
          when "tango_string_split"
            return unsupported(node) if node.block || node.args.size > 1

            recv = translate_expr(receiver)
            separator = node.args.first?.try { |arg| translate_expr(arg) }
            IR::NIR::StringSplit.new(next_id, recv, type_of(node), span(node), separator, method_site: method_site(node, recv))
          when "tango_string_to_f"
            return unsupported(node) if node.block || !node.args.empty?

            recv = translate_expr(receiver)
            IR::NIR::StringToFloat.new(next_id, recv, type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_string_to_integer"
            return unsupported(node) if node.block || node.args.size != 6

            recv = translate_expr(receiver)
            options = node.args.map { |arg| translate_expr(arg) }
            IR::NIR::StringToInteger.new(next_id, recv, options, type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_string_size"
            return unsupported(node) if node.block || !node.args.empty?

            recv = translate_expr(receiver)
            IR::NIR::Size.new(next_id, recv, type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_string_char_at"
            return unsupported(node) if node.block || node.args.size != 1

            recv = translate_expr(receiver)
            IR::NIR::StringCharAt.new(next_id, recv, translate_expr(node.args.first), type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_string_each_char"
            crystal_block = node.block
            return unsupported(node) unless crystal_block && node.args.empty?

            recv = translate_expr(receiver)
            block = translate_block_literal(crystal_block)
            IR::NIR::StringEachChar.new(next_id, recv, block, type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_hash_new", "tango_hash_get", "tango_hash_set", "tango_hash_fetch", "tango_hash_size", "tango_hash_has_key", "tango_hash_key_at"
            translate_hash_call(node, receiver, symbol)
          when "tango_array_new"
            return unsupported(node) if node.block || !node.args.empty?

            element = array_element(type_of(node))
            IR::NIR::ArrayNew.new(next_id, element, type_of(node), span(node))
          when "tango_array_build"
            return unsupported(node) if node.block || node.args.size != 1

            element = array_element(type_of(node))
            IR::NIR::ArrayBuild.new(next_id, element, translate_expr(node.args.first), type_of(node), span(node))
          when "tango_array_get"
            return unsupported(node) if node.block || node.args.size != 1

            recv = translate_expr(receiver)
            element = array_element(type_of(receiver))
            IR::NIR::ArrayGet.new(next_id, recv, translate_expr(node.args.first), element, type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_array_set"
            return unsupported(node) if node.block || node.args.size != 2

            recv = translate_expr(receiver)
            element = array_element(type_of(receiver))
            IR::NIR::ArraySet.new(next_id, recv, translate_expr(node.args[0]), translate_expr(node.args[1]), element, type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_array_size"
            return unsupported(node) if node.block || !node.args.empty?

            recv = translate_expr(receiver)
            IR::NIR::Size.new(next_id, recv, type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_array_push"
            return unsupported(node) if node.block || node.args.size != 1

            recv = translate_expr(receiver)
            element = array_element(type_of(receiver))
            IR::NIR::ArrayPush.new(next_id, recv, translate_expr(node.args.first), element, type_of(node), span(node), method_site: method_site(node, recv))
          when "tango_mutex_new"
            return unsupported(node) if node.block || !node.args.empty?

            IR::NIR::MutexNew.new(next_id, type_of(node), span(node))
          when "tango_chan_new"
            return unsupported(node) if node.block || node.args.size > 1

            capacity = node.args.first?.try { |arg| translate_expr(arg) }
            IR::NIR::ChannelNew.new(next_id, channel_element(type_of(node)), capacity, type_of(node), span(node))
          when "tango_chan_send", "tango_chan_receive", "tango_chan_receive_q", "tango_chan_next_state", "tango_chan_close"
            return unsupported(node) if node.block

            recv = translate_expr(receiver)
            value = node.args.first?.try { |arg| translate_expr(arg) }
            IR::NIR::ChannelOp.new(next_id, channel_op_kind(symbol), recv, value, channel_element(type_of(receiver)), type_of(node), span(node), method_site: method_site(node, recv))
          end
        end

        private def translate_implicit_call(node : ::Crystal::Call, call_targets : Array(IR::NIR::CallTarget)) : IR::NIR::Expr
          if tango_primitive(call_targets) == "tango_array_size"
            return unsupported(node) if node.block || !node.args.empty?
            owner_type = implicit_array_owner_type(node)
            return unsupported(node) unless owner_type

            recv = IR::NIR::Local.new(next_id, "self", owner_type, span(node))
            return IR::NIR::Size.new(next_id, recv, type_of(node), span(node), method_site: method_site(node, recv))
          end

          if symbol = tango_primitive(call_targets)
            if hash_primitive?(symbol)
              owner_type = implicit_instance_owner_type(node)
              return unsupported(node) unless owner_type
              return translate_implicit_hash_call(node, owner_type, symbol)
            end
          end

          if tango_primitive(call_targets) == "tango_go"
            return unsupported(node) unless node.args.size == 1 && !node.block

            return IR::NIR::Spawn.new(next_id, translate_expr(node.args.first), type_of(node), span(node))
          end

          queue_defs(node)
          args = [] of IR::NIR::Expr
          if owner_type = implicit_instance_owner_type(node)
            args << IR::NIR::Local.new(next_id, "self", owner_type, span(node))
          end
          args.concat(node.args.map { |arg| translate_expr(arg) })
          block = node.block.try { |inline_block| translate_block_literal(inline_block) }
          IR::NIR::Call.new(next_id, node.name, args, call_targets, block, type_of(node), span(node), name_span: name_span(node.name_location, node.name))
        end

        private def translate_receiver_call_args(node : ::Crystal::Call, receiver : ::Crystal::ASTNode) : Array(IR::NIR::Expr)
          args = [] of IR::NIR::Expr
          args << translate_expr(receiver) unless class_receiver?(receiver)
          args.concat(node.args.map { |arg| translate_expr(arg) })
          args
        end

        private def explicit_method_site(node : ::Crystal::Call, receiver : ::Crystal::ASTNode, args : Array(IR::NIR::Expr)) : IR::NIR::MethodSite
          if class_receiver?(receiver)
            method_site(node, class_receiver_type(receiver), IR::NIR::CallableKind::ClassMethod)
          else
            method_site(node, args.first)
          end
        end

        private def class_dispatch_receiver(receiver : ::Crystal::ASTNode) : IR::NIR::ClassRef?
          return unless class_receiver?(receiver)

          type = class_receiver_type(receiver)
          name = type.name || type.to_s
          range = name_span(receiver.location, name) || span(receiver)
          IR::NIR::ClassRef.new(next_id, name, type, range, range)
        end

        private def class_receiver_type(receiver : ::Crystal::ASTNode) : IR::Type
          crystal_type = receiver.type?
          return IR::Type.unknown unless crystal_type

          build_type(crystal_type.instance_type)
        end

        private def class_receiver?(receiver : ::Crystal::ASTNode) : Bool
          receiver.type?.try(&.metaclass?) || false
        end

        private def implicit_instance_owner_type(node : ::Crystal::Call) : IR::Type?
          target = node.target_defs.try(&.first?)
          owner = target.try(&.owner?)
          return nil unless owner
          return nil if owner.is_a?(::Crystal::Program) || owner.metaclass?
          build_type(owner)
        end

        private def queue_defs(node : ::Crystal::Call) : Nil
          node.target_defs.try do |defs|
            defs.each do |target_def|
              next unless internal_def?(target_def)
              @state.queue(target_def)
            end
          end
        end

        private def internal_def?(target_def : ::Crystal::Def) : Bool
          annotations(target_def).none? { |ann| ann.path == ["Go"] || ann.path == ["Primitive"] }
        end
      end
    end
  end
end
