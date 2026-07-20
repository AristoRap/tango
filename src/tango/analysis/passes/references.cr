module Tango
  module Analysis
    module Passes
      # Records reference→declaration edges every navigation consumer
      # (goto-definition, hover) resolves through one uniform span→edge lookup:
      # a `.new` names a class (type_refs); an instance-var access names a field
      # of its owning class (field_refs); a local/param/block-arg reference names
      # its binding declaration (local_refs).
      #
      # Locals have no global name, so their edge is resolved by lexical scope
      # rather than a name table: a def opens a fresh scope (defs do not capture
      # enclosing locals); a block opens a nested scope chained to its encloser
      # (blocks capture by reference); the first assignment to a name in a scope
      # is its declaration, later assignments and reads reference it.
      class References
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          scope = Scope.new(nil)
          IR::NIR::Walk.children(program).each { |stmt| visit(stmt, scope, table) }
          classify_local_use(table)
        end

        # A lexical scope: name → declaring NodeId, chained to its parent so a
        # nested block resolves a captured local by walking outward.
        private class Scope
          getter parent : Scope?
          getter declarations = Hash(String, NodeId).new

          def initialize(@parent : Scope?)
          end

          def resolve(name : String) : NodeId?
            declarations[name]? || parent.try(&.resolve(name))
          end
        end

        private def visit(node : IR::NIR::Stmt, scope : Scope, table : Facts::Table) : Nil
          case node
          when IR::NIR::New
            table.references[node.id] = Facts::ClassReference.new(node.class_name)
          when IR::NIR::ClassRef
            table.references[node.id] = Facts::ClassReference.new(node.name)
          when IR::NIR::InstanceVar
            table.references[node.id] = Facts::FieldReference.new(node.owner, node.name)
          when IR::NIR::EnumMember
            table.references[node.id] = Facts::EnumMemberReference.new(node.enum_type, node.name)
          when IR::NIR::Local
            # A Local reached here is a read — assignment targets are consumed by
            # the Assign case, which never recurses into its target as a read.
            record_local_read(node.id, node.name, scope, table)
          when IR::NIR::Assign
            visit_assign(node, scope, table)
            return
          when IR::NIR::Def
            inner = Scope.new(nil)
            node.params.each { |param| declare(inner, param.name, param.id) }
            node.block_param.try { |block_param| declare(inner, block_param.name, block_param.id) }
            visit(node.body, inner, table)
            return
          when IR::NIR::BlockLiteral
            inner = Scope.new(scope)
            node.args.each { |arg| declare(inner, arg.name, arg.id) }
            visit(node.body, inner, table)
            return
          when IR::NIR::Select
            # Each arm's channel/value reads enclosing locals; the body opens a
            # nested scope where a receive-assign binds its captured local.
            node.arms.each do |arm|
              visit(arm.channel, scope, table)
              arm.value.try { |value| visit(value, scope, table) }
              inner = Scope.new(scope)
              arm.captured.try { |captured| declare(inner, captured.name, captured.id) }
              visit(arm.body, inner, table)
            end
            node.else_body.try { |else_body| visit(else_body, Scope.new(scope), table) }
            return
          when IR::NIR::ExceptionHandler
            visit(node.body, scope, table)
            node.clauses.each do |clause|
              inner = Scope.new(scope)
              clause.binding.try { |binding| declare(inner, binding.name, binding.id) }
              visit(clause.body, inner, table)
            end
            node.else_branch.try { |branch| visit(branch, scope, table) }
            node.ensure_branch.try { |branch| visit(branch, scope, table) }
            return
          end

          IR::NIR::Walk.children(node).each { |child| visit(child, scope, table) }
        end

        private def visit_assign(node : IR::NIR::Assign, scope : Scope, table : Facts::Table) : Nil
          target = node.target
          if target.is_a?(IR::NIR::Local)
            # First assignment in a scope declares; a later one, or an assignment
            # to a name already visible in an enclosing scope (a captured write),
            # references that binding rather than shadowing it.
            if scope.declarations.has_key?(target.name) || captured_from_enclosing?(scope, target.name)
              record_local_write(target.id, target.name, scope, table)
            else
              declare(scope, target.name, target.id)
              table.local_bindings[target.id] = Facts::LocalBinding.new(target.name)
              table.local_writes[target.id] = target.id
            end
          else
            visit(target, scope, table)
          end
          visit(node.value, scope, table)
        end

        private def captured_from_enclosing?(scope : Scope, name : String) : Bool
          parent = scope.parent
          !parent.nil? && !parent.resolve(name).nil?
        end

        private def declare(scope : Scope, name : String, id : NodeId) : Nil
          scope.declarations[name] = id unless scope.declarations.has_key?(name)
        end

        private def record_local_read(id : NodeId, name : String, scope : Scope, table : Facts::Table) : Nil
          declaration = scope.resolve(name)
          return unless declaration
          return if declaration == id
          table.references[id] = Facts::LocalReference.new(declaration)
          table.binding_uses << declaration
          # Navigation resolves reads and writes alike, but only a value read
          # keeps a local slot alive in the Go lowering.
          table.local_reads << declaration if table.local_bindings.has_key?(declaration)
        end

        private def record_local_write(id : NodeId, name : String, scope : Scope, table : Facts::Table) : Nil
          declaration = scope.resolve(name)
          return unless declaration
          table.references[id] = Facts::LocalReference.new(declaration) unless declaration == id
          table.local_writes[id] = declaration if table.local_bindings.has_key?(declaration)
        end

        private def classify_local_use(table : Facts::Table) : Nil
          table.local_bindings.each do |declaration, binding|
            next if table.local_reads.includes?(declaration)

            table.local_writes.each do |write, target|
              table.unread_local_writes << write if target == declaration
            end
            table.unused_locals << declaration unless binding.name.starts_with?('_')
          end
        end
      end
    end
  end
end
