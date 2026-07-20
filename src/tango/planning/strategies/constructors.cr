module Tango
  module Planning
    module Strategies
      # Names the constructor each `.new` lowers to. Its initializer comes from
      # the concrete call-to-def edge and the selected def's monomorph plan, so
      # overloaded initializers cannot drift from ordinary call planning.
      class Constructors
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          IR::NIR::Walk.children(program).each { |stmt| visit(stmt, facts, table) }
        end

        private def visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          if node.is_a?(IR::NIR::New)
            arg_types = node.args.map { |arg| arg.type || IR::Type.unknown }
            owner_type = node.type || IR::Type.klass(node.class_name)
            owner_name = owner_type.name || node.class_name
            layout_identity = owner_type.to_s
            resolved = facts.internal_calls[node.id]?
            definition = resolved.try { |call| table.monomorphs[call.definition]? }
            if !node.invokes_initializer? || definition
              table.constructors[node.id] = Plans::Constructor.new(
                Mangle.func_name("#{owner_name}_new", arg_types),
                definition.try(&.name),
                owner_type,
                arg_types,
                (table.layouts[layout_identity]? || table.layouts[owner_name]?).try(&.reference) != false
              )
            end
          end

          IR::NIR::Walk.children(node).each { |child| visit(child, facts, table) }
        end
      end
    end
  end
end
