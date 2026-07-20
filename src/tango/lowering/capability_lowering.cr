module Tango
  module Lowering
    module CapabilityLowering
      # Static capability specialization is committed by the concrete Func
      # parameter/owner and the already planned concrete call names. Validate
      # that every analysis witness has that plan before emitting the body so a
      # future dispatch strategy cannot silently ride the static LIR shape.
      private def commit_capability_dispatch(node : IR::NIR::Def, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : Nil
        conformances = facts.capability_conformances[node.id]?
        return unless conformances

        dispatches = plans.capability_dispatches[node.id]? || raise "missing capability dispatch plan for #{node.id}"
        unless dispatches.size == conformances.size
          raise "capability dispatch count mismatch for #{node.id}"
        end

        conformances.each_with_index do |conformance, index|
          dispatch = dispatches[index]
          unless dispatch.concrete == conformance.concrete &&
                 dispatch.capability == conformance.capability &&
                 dispatch.strategy.static_specialization?
            raise "uncommitted capability dispatch for #{node.id}"
          end
        end
      end
    end
  end
end
