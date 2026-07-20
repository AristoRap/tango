require "../spec_helper"
require "../../src/tango/dump"

describe "capability dispatch example" do
  source_path = File.join("examples", "capability_dispatch.tn")
  snapshot = Tango.snapshot(File.read(source_path), filename: source_path)

  it "preserves resolved witnesses and static dispatch through every phase" do
    nir = Tango::Dump::NIR.render(snapshot)
    facts = Tango::Dump::Facts.render(snapshot)
    plans = Tango::Dump::Plans.render(snapshot)
    lir = Tango::Dump::LIR.render(snapshot)

    nir.should contain("capabilities=[Array(Int32) as Enumerable(Int32)]")
    nir.should contain("capabilities=[Range(Int32, Int32) as Enumerable(Int32)]")
    nir.should contain("capabilities=[String as Sized]")
    nir.should contain("Size : Int32")

    facts.should contain("capability_conformance Array(Int32) as Enumerable(Int32)")
    facts.should contain("capability_conformance Range(Int32, Int32) as Enumerable(Int32)")
    facts.should contain("capability_conformance String as Sized")

    plans.should contain("capability_dispatch StaticSpecialization Array(Int32) as Enumerable(Int32)")
    plans.should contain("capability_dispatch StaticSpecialization Range(Int32, Int32) as Enumerable(Int32)")
    plans.should contain("capability_dispatch StaticSpecialization String as Sized")

    lir.should contain("Func sum_Array")
    lir.should contain("Func sum_Range")
    lir.should contain("Func emptyu3f__String")
  end
end
