module Tango
  module Frontend
    module Crystal
      # Resolved call identity and annotation metadata crossing the Crystal-to-NIR
      # boundary. ToNIR owns translation state; this reopening keeps the complete
      # call-target projection separate from syntax dispatch.
      class ToNIR
        private def targets(node : ::Crystal::Call) : Array(IR::NIR::CallTarget)
          node.target_defs.try do |defs|
            defs.map do |target_def|
              IR::NIR::CallTarget.new(
                target_def.name,
                target_def.owner?.try(&.to_s),
                annotations(target_def),
                definition_namespace_path(target_def.owner?)
              )
            end
          end || [] of IR::NIR::CallTarget
        end

        private def annotations(target_def : ::Crystal::Def) : Array(IR::NIR::TargetAnnotation)
          target_annotations(target_def.all_annotations)
        end

        private def target_annotations(all_annotations : Array(::Crystal::Annotation)?) : Array(IR::NIR::TargetAnnotation)
          all_annotations.try do |values|
            values.map do |ann|
              IR::NIR::TargetAnnotation.new(ann.path.names, string_args(ann), symbol_args(ann))
            end
          end || [] of IR::NIR::TargetAnnotation
        end

        private def external_target?(targets : Array(IR::NIR::CallTarget)) : Bool
          targets.any? { |target| target.annotations.any? { |ann| ann.path == ["Go"] } }
        end

        private def proc_call_target?(targets : Array(IR::NIR::CallTarget)) : Bool
          targets.any? do |target|
            target.annotations.any? { |ann| ann.path == ["Primitive"] && ann.symbol_args.includes?("proc_call") }
          end
        end

        # The proc signature of a `&block` parameter, read from its resolved
        # Crystal type so the frontend steals the arity and element types.
        private def proc_signature(node : ::Crystal::ASTNode) : IR::NIR::ProcSignature
          type = node.type?
          if type.is_a?(::Crystal::ProcInstanceType)
            return_type = build_type(type.return_type)
            return IR::NIR::ProcSignature.new(
              type.arg_types.map { |arg_type| build_type(arg_type) },
              return_type.nil_type? ? nil : return_type
            )
          end
          IR::NIR::ProcSignature.new([] of IR::Type, nil)
        end

        # The first `@[Primitive(:sym)]` symbol among a call's targets, as a bare
        # string. Distinct from `primitive_kind`, which only recognizes the
        # inline binary/arith kinds; the concurrency primitives dispatch to their
        # own structured nodes rather than a `Primitive` tag.
        private def tango_primitive(targets : Array(IR::NIR::CallTarget)) : String?
          targets.each do |target|
            target.annotations.each do |ann|
              next unless ann.path == ["Primitive"]
              symbol = ann.symbol_args.first?
              return symbol if symbol
            end
          end
          nil
        end

        private def channel_op_kind(symbol : String) : IR::NIR::ChannelOp::Kind
          case symbol
          when "tango_chan_send"       then IR::NIR::ChannelOp::Kind::Send
          when "tango_chan_receive"    then IR::NIR::ChannelOp::Kind::Receive
          when "tango_chan_receive_q"  then IR::NIR::ChannelOp::Kind::ReceiveMaybe
          when "tango_chan_next_state" then IR::NIR::ChannelOp::Kind::NextState
          when "tango_chan_close"      then IR::NIR::ChannelOp::Kind::Close
          else
            raise ArgumentError.new("unknown channel primitive #{symbol}")
          end
        end

        private def channel_element(type : IR::Type?) : IR::Type
          type.try(&.type_args.first?) || IR::Type.unknown
        end

        private def primitive_kind(targets : Array(IR::NIR::CallTarget)) : IR::NIR::Primitive::Kind?
          targets.each do |target|
            target.annotations.each do |ann|
              next unless ann.path == ["Primitive"]
              kind = IR::NIR::Primitive::Kind.from_annotation(ann.symbol_args.first?)
              return kind if kind
            end
          end
          nil
        end

        private def string_args(ann : ::Crystal::Annotation) : Array(String)
          ann.args.compact_map do |arg|
            arg.as?(::Crystal::StringLiteral).try(&.value)
          end
        end

        private def symbol_args(ann : ::Crystal::Annotation) : Array(String)
          ann.args.compact_map do |arg|
            arg.as?(::Crystal::SymbolLiteral).try(&.value)
          end
        end

        private def method_site(node : ::Crystal::Call, receiver : IR::NIR::Expr, kind : IR::NIR::CallableKind = IR::NIR::CallableKind::InstanceMethod) : IR::NIR::MethodSite
          method_site(node, receiver.type || IR::Type.unknown, kind)
        end

        private def method_site(node : ::Crystal::Call, owner : IR::Type, kind : IR::NIR::CallableKind) : IR::NIR::MethodSite
          IR::NIR::MethodSite.new(
            owner,
            node.name,
            node.args.map { |arg| type_of(arg) || IR::Type.unknown },
            type_of(node) || IR::Type.unknown,
            name_span(node.name_location, node.name),
            kind
          )
        end
      end
    end
  end
end
