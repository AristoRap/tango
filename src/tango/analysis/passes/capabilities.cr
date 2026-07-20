module Tango
  module Analysis
    module Passes
      # Copies Crystal-proven module witnesses into the analysis vocabulary.
      # No inclusion or abstract-method relation is reconstructed here.
      class Capabilities
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          IR::NIR::Walk.children(program).each do |stmt|
            next unless stmt.is_a?(IR::NIR::Def)
            next if stmt.capability_witnesses.empty?

            table.capability_conformances[stmt.id] = stmt.capability_witnesses.dup
          end
        end
      end
    end
  end
end
