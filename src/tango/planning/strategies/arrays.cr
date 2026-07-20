module Tango
  module Planning
    module Strategies
      class Arrays
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.types.arrays.each do |type|
            element = type.element_type || IR::Type.unknown
            table.arrays[type] = Plans::ArrayRepr.new(type, element, reference: true)
          end
        end
      end
    end
  end
end
