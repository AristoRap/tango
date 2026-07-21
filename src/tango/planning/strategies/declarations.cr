module Tango
  module Planning
    module Strategies
      class Declarations
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.namespaces.each do |id, definition|
            table.namespaces[id] = Plans::NamespacePlan.new(definition.path, Mangle.path_name(definition.path))
          end
          facts.constants.each_value do |definition|
            table.constants[definition.declaration] = Plans::ConstantPlan.new(
              definition.path,
              Mangle.path_name(definition.path),
              definition.type
            )
          end
          facts.type_aliases.each_value do |definition|
            table.type_aliases[definition.declaration] = Plans::TypeAliasPlan.new(definition.path, definition.target)
          end
        end
      end
    end
  end
end
