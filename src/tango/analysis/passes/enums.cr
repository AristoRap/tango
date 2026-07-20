module Tango
  module Analysis
    module Passes
      class Enums
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          IR::NIR::Walk.children(program).each do |node|
            next unless node.is_a?(IR::NIR::Enum)
            members = node.members.map { |member| Facts::EnumMember.new(member.name, member.value) }
            table.enums[node.type] = Facts::EnumDefinition.new(node.type, node.base_type, members)
          end
        end
      end
    end
  end
end
