require "../spec_helper"
require "../../src/tango/dump"

describe "Comparable capability" do
  source_path = File.join("examples", "comparable.tn")
  snapshot = Tango.snapshot(File.read(source_path), filename: source_path)

  it "preserves instantiated witnesses and static specialization through every phase" do
    nir = Tango::Dump::NIR.render(snapshot)
    facts = Tango::Dump::Facts.render(snapshot)
    plans = Tango::Dump::Plans.render(snapshot)
    lir = Tango::Dump::LIR.render(snapshot)

    {"Int32", "String", "Float64", "Score"}.each do |type|
      witness = "#{type} as Comparable(#{type})"
      nir.should contain("capabilities=[#{witness}]")
      facts.should contain("capability_conformance #{witness}")
      plans.should contain("capability_dispatch StaticSpecialization #{witness}")
      lir.should contain("Func before__or__equal_#{type}_#{type}")
    end

    reference_witness = "UnorderedReference as Comparable(UnorderedReference)"
    facts.should contain("capability_conformance #{reference_witness}")
    plans.should contain("capability_dispatch StaticSpecialization #{reference_witness}")
    nir.should contain("same? primitive ReferenceIdentity : Bool")
    lir.should contain("Func u3d_u3d__UnorderedReference_UnorderedReference")
  end

  it "keeps Float64 ordering partial at NaN and total for supported integer and String values" do
    output = IO::Memory.new
    error = IO::Memory.new
    result = Tango::Toolchain::Go.run_source(Tango.compile(File.read(source_path), filename: source_path), source_path, output, error)

    error.to_s.should be_empty
    result.status.should eq(0)
    result.diagnostics.should be_empty
    output.to_s.should eq(File.read("spec/golden/comparable.stdout"))
  end

  it "preserves value-struct identity in hover presentation" do
    hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 5, 8))
    Tango::Compiler::Editor::HoverText.render(hover).should eq("struct Score")
    Tango::Compiler::Editor::HoverMarkdown.render(hover).should contain("struct Score")
  end
end
