module Tango
  module Planning
    module Strategies
      # Commits each admitted scalar type to Tango's presentation category.
      class Stringifications
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.scalar_stringifications.each do |id, fact|
            presentation = case fact.type.family
                           when .int?    then IR::ScalarPresentation::Integer
                           when .float?  then IR::ScalarPresentation::Float
                           when .bool?   then IR::ScalarPresentation::Bool
                           when .string? then IR::ScalarPresentation::String
                           when .null?   then IR::ScalarPresentation::Nil
                           else               raise "unhandled scalar presentation type #{fact.type}"
                           end
            table.scalar_stringifications[id] = Plans::ScalarStringificationPlan.new(fact.type, presentation)
          end
        end
      end
    end
  end
end
