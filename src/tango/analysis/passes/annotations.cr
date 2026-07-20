module Tango
  module Analysis
    module Passes
      class Annotations
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          program.type_annotations.each do |type, entries|
            entries.each do |entry|
              binding = external_type(type, entry)
              table.external_types[type] = binding if binding
            end
          end
          IR::NIR::Walk.children(program).each { |stmt| visit(stmt, table) }
        end

        private def visit(node : IR::NIR::Stmt, table : Facts::Table) : Nil
          if node.is_a?(IR::NIR::Call)
            go_externals = node.targets.flat_map { |target| target.annotations.compact_map { |ann| go_external(ann) } }
            table.go_externals[node.id] = go_externals unless go_externals.empty?
          end

          IR::NIR::Walk.non_binding_children(node).each { |child| visit(child, table) }
        end

        private def go_external(ann : IR::NIR::TargetAnnotation) : Facts::GoExternal?
          return nil unless ann.path == ["Go"]

          ann.string_args.first?.try { |value| Facts::GoExternal.parse(value) }
        end

        private def external_type(type : IR::Type, ann : IR::NIR::TargetAnnotation) : IR::ExternalType?
          return nil unless ann.path == ["GoType"]

          if ann.symbol_args.includes?("native_channel")
            binding = IR::ExternalBinding.new("go")
            return IR::ExternalType.new(type, binding, IR::ExternalType::Shape::NativeChannel)
          end

          qualified = ann.string_args.first?
          return nil unless qualified
          binding = IR::ExternalBinding.qualified("go", qualified)
          shape = ann.symbol_args.includes?("pointer") ? IR::ExternalType::Shape::NamedPointer : IR::ExternalType::Shape::NamedValue
          IR::ExternalType.new(type, binding, shape)
        end
      end
    end
  end
end
