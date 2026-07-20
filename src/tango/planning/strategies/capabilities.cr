module Tango
  module Planning
    module Strategies
      # The initial capability-dispatch layer only admits typed defs that Crystal
      # has already specialized to a concrete argument/owner. Future forced
      # union or interface cases can extend the strategy enum without changing
      # the public capability contract.
      class Capabilities
        def self.run(_program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.capability_conformances.each do |id, conformances|
            table.capability_dispatches[id] = conformances.map do |conformance|
              Plans::CapabilityDispatch.new(
                conformance.concrete,
                conformance.capability,
                Plans::CapabilityDispatch::Strategy::StaticSpecialization
              )
            end
          end
        end
      end
    end
  end
end
