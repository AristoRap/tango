require "../../spec_helper"

describe Tango::Planning::Strategies::Arrays do
  it "chooses the pointer-slice representation required by Array aliasing" do
    i32 = Tango::IR::Type.int(:i32)
    array = Tango::IR::Type.array(i32)
    facts = Tango::Analysis::Facts::Table.new
    facts.types.arrays << array
    plans = Tango::Planning::Plans::Table.new

    Tango::Planning::Strategies::Arrays.run(Tango::IR::NIR::Program.new([] of Tango::IR::NIR::Stmt), facts, plans)

    repr = plans.arrays[array]
    repr.reference?.should be_true
    repr.element.should eq(i32)
  end
end
