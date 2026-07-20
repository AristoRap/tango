module Tango
  module Frontend
    module Crystal
      module CoreDispatchTranslation
        private def translate_type_test(node : ::Crystal::IsA) : IR::NIR::Expr
          if replacement = node.syntax_replacement
            return translate_expr(replacement)
          end

          target = node.const.type?.try(&.instance_type)
          return unsupported(node) unless target
          IR::NIR::TypeTest.new(next_id, translate_expr(node.obj), build_type(target), type_of(node), span(node))
        end

        private def translate_cast(node : ::Crystal::Cast) : IR::NIR::Expr
          target = type_of(node)
          return unsupported(node) unless target
          IR::NIR::Cast.new(next_id, translate_expr(node.obj), target, type_of(node), span(node))
        end
      end
    end
  end
end
