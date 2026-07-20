module Tango
  module Analysis
    module Passes
      # Records the ordered instance-var layout of each class from its NIR
      # node. Analysis proves the layout; planning chooses its representation.
      class Layout
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          classes = IR::NIR::Walk.children(program).compact_map(&.as?(IR::NIR::Class))
          by_name = classes.to_h { |node| {node.layout_identity, node} }

          classes.each do |stmt|
            table.struct_layouts[stmt.layout_identity] = Facts::StructLayout.new(stmt.fields.dup, stmt.reference?)
            exception_ancestors(stmt, by_name).try do |ancestors|
              table.exception_hierarchies[stmt.layout_identity] = Facts::ExceptionHierarchy.new(ancestors)
            end
          end
        end

        private def exception_ancestors(node : IR::NIR::Class, classes : Hash(String, IR::NIR::Class), seen = Set(String).new) : Array(String)?
          return nil if seen.includes?(node.layout_identity)
          seen << node.layout_identity

          superclass = node.superclass_name
          return nil unless superclass
          return [node.layout_identity, IR::Type::EXCEPTION_ROOT_NAME] if superclass == IR::Type::EXCEPTION_ROOT_NAME

          parent = classes[superclass]?
          parent.try { |klass| exception_ancestors(klass, classes, seen).try { |ancestors| [node.layout_identity] + ancestors } }
        end
      end
    end
  end
end
