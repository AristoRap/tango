require "../../spec_helper"

describe Tango::Planning::Strategies::Capabilities do
  it "selects static specialization for every resolved concrete witness" do
    id = Tango::NodeId.new("sum")
    concrete = Tango::IR::Type.array(Tango::IR::Type.int(:i32))
    capability = Tango::IR::Type.klass("Enumerable", [Tango::IR::Type.int(:i32)])
    facts = Tango::Analysis::Facts::Table.new
    facts.capability_conformances[id] = [
      Tango::Analysis::Facts::CapabilityConformance.new(concrete, capability),
    ]
    plans = Tango::Planning::Plans::Table.new

    program = Tango::IR::NIR::Program.new([] of Tango::IR::NIR::Stmt)
    Tango::Planning::Strategies::Capabilities.run(program, facts, plans)

    dispatch = plans.capability_dispatches[id].first
    dispatch.concrete.should eq(concrete)
    dispatch.capability.should eq(capability)
    dispatch.strategy.static_specialization?.should be_true
  end
end
