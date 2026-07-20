module Tango
  module Frontend
    module Crystal
      # Translation helpers for call-site blocks and yield-def bodies. Crystal
      # has already inferred every argument/result type; this module preserves
      # those signatures and turns a yield into an invocation of the enclosing
      # def's synthetic block parameter.
      module YieldTranslation
        private def translate_block_literal(node : ::Crystal::Block) : IR::NIR::BlockLiteral
          args = node.args.map { |arg| IR::NIR::BlockArg.new(next_id, arg.name, span(arg), name_span: name_span(arg.location, arg.name)) }
          param_types = node.args.map { |arg| type_of(arg) || IR::Type.unknown }
          return_type = type_of(node.body)
          return_type = nil if return_type.try(&.nil_type?)
          signature = IR::NIR::ProcSignature.new(param_types, return_type)
          IR::NIR::BlockLiteral.new(next_id, args, translate_block(node.body), signature, type_of(node), span(node))
        end

        private def translate_yield(node : ::Crystal::Yield) : IR::NIR::Expr
          block_param = @context.yield_param
          return unsupported(node) unless block_param

          receiver = IR::NIR::Local.new(next_id, block_param.name, block_param.signature.to_type, span(node))
          arity = block_param.signature.param_types.size
          args = node.exps.first(arity).map { |arg| translate_expr(arg) }
          IR::NIR::InvokeBlock.new(next_id, receiver, args, type_of(node), span(node), yield_site: true)
        end

        private class YieldCollector < ::Crystal::Visitor
          getter yields = [] of ::Crystal::Yield

          def visit(node : ::Crystal::Yield) : Bool
            @yields << node
            true
          end

          def visit(node : ::Crystal::Def) : Bool
            false
          end

          def visit(node : ::Crystal::ASTNode) : Bool
            true
          end
        end

        private def collect_yields(node : ::Crystal::ASTNode) : Array(::Crystal::Yield)
          collector = YieldCollector.new
          node.accept(collector)
          collector.yields
        end

        private def yield_signature(node : ::Crystal::Def, yields : Array(::Crystal::Yield)) : IR::NIR::ProcSignature
          param_types = node.yield_vars.try do |vars|
            vars.map { |var| var.type?.try { |type| build_type(type) } || IR::Type.unknown }
          end || yields.first.exps.first(node.block_arity || yields.first.exps.size).map { |arg| type_of(arg) || IR::Type.unknown }

          return_type = type_of(yields.first)
          return_type = nil if return_type.try(&.nil_type?)
          IR::NIR::ProcSignature.new(param_types, return_type)
        end

        private def yield_value_required?(block_arg : ::Crystal::Arg?, signature : IR::NIR::ProcSignature) : Bool
          if restriction = block_arg.try(&.restriction)
            if restriction.is_a?(::Crystal::ProcNotation)
              output = restriction.output
              return false unless output
              return false if output.is_a?(::Crystal::Path) && output.names == ["Nil"]
              return true
            end
          end
          !signature.return_type.nil?
        end
      end
    end
  end
end
