module Tango
  module Planning
    module Strategies
      class Enums
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.enums.each do |type, definition|
            target_name = Mangle.sanitize(type.to_s)
            members = definition.members.map do |member|
              Plans::EnumRepr::Member.new(
                member.name,
                member.value,
                "#{target_name}_#{Mangle.sanitize(member.name)}"
              )
            end
            table.enums[type] = Plans::EnumRepr.new(type, target_name, definition.base_type, members)
          end
        end
      end
    end
  end
end
