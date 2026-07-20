module Tango
  module Frontend
    module Crystal
      module HashTranslation
        private def translate_hash_call(node : ::Crystal::Call, receiver : ::Crystal::ASTNode, symbol : String) : IR::NIR::Expr
          if symbol == "tango_hash_new"
            owner_type = type_of(node) || IR::Type.hash(IR::Type.unknown, IR::Type.unknown)
            return build_hash_call(node, nil, owner_type, symbol)
          end

          recv = translate_expr(receiver)
          build_hash_call(node, recv, type_of(receiver) || IR::Type.unknown, symbol)
        end

        private def translate_implicit_hash_call(node : ::Crystal::Call, owner_type : IR::Type, symbol : String) : IR::NIR::Expr
          recv = IR::NIR::Local.new(next_id, "self", owner_type, span(node))
          build_hash_call(node, recv, owner_type, symbol)
        end

        private def build_hash_call(node : ::Crystal::Call, recv : IR::NIR::Expr?, owner_type : IR::Type, symbol : String) : IR::NIR::Expr
          if symbol == "tango_hash_new"
            return unsupported(node) if node.block || !node.args.empty?
            site = method_site(node, owner_type, IR::NIR::CallableKind::Constructor)
            return IR::NIR::HashNew.new(next_id, owner_type, type_of(node), span(node), site)
          end

          receiver = recv || return unsupported(node)
          site = method_site(node, receiver)
          case symbol
          when "tango_hash_get"
            return unsupported(node) if node.block || node.args.size != 1
            IR::NIR::HashGet.new(next_id, receiver, translate_expr(node.args[0]), owner_type, type_of(node), span(node), site)
          when "tango_hash_set"
            return unsupported(node) if node.block || node.args.size != 2
            IR::NIR::HashSet.new(next_id, receiver, translate_expr(node.args[0]), translate_expr(node.args[1]), owner_type, type_of(node), span(node), site)
          when "tango_hash_fetch"
            return unsupported(node) if node.block || node.args.size != 2
            IR::NIR::HashFetch.new(next_id, receiver, translate_expr(node.args[0]), translate_expr(node.args[1]), owner_type, type_of(node), span(node), site)
          when "tango_hash_size"
            return unsupported(node) if node.block || !node.args.empty?
            IR::NIR::Size.new(next_id, receiver, type_of(node), span(node), site)
          when "tango_hash_has_key"
            return unsupported(node) if node.block || node.args.size != 1
            IR::NIR::HashHasKey.new(next_id, receiver, translate_expr(node.args[0]), owner_type, type_of(node), span(node), site)
          when "tango_hash_key_at"
            return unsupported(node) if node.block || node.args.size != 1
            IR::NIR::HashKeyAt.new(next_id, receiver, translate_expr(node.args[0]), owner_type, type_of(node), span(node), site)
          else
            unsupported(node)
          end
        end

        private def hash_primitive?(symbol : String?) : Bool
          !!symbol && symbol.starts_with?("tango_hash_")
        end
      end
    end
  end
end
