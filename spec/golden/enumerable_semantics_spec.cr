require "../spec_helper"
require "../../src/tango/dump"

describe "enumerable semantic fallback" do
  source_path = File.join("examples", "enumerable.tn")
  snapshot = Tango.snapshot(File.read(source_path), filename: source_path)

  it "preserves semantic transforms and their conservative plan through the pipeline" do
    nir = Tango::Dump::NIR.render(snapshot)
    plans = Tango::Dump::Plans.render(snapshot)
    lir = Tango::Dump::LIR.render(snapshot)

    nir.should contain("CollectionMap fallback=map : Array(Int32)")
    nir.should contain("CollectionFilter Keep fallback=select : Array(Int32)")
    plans.scan("semantic_collection MaterializeViaFallback Array(Int32)").size.should be >= 2
    lir.should contain("Call map_Array")
    lir.should contain("Call select_Array")
    lir.should_not contain("Unsupported")
  end

  it "retains ordinary method-site hover on semantic calls" do
    select_hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 2, 9))
    map_hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 2, 30))

    Tango::Compiler::Editor::HoverText.render(select_hover).should eq("Array(Int32)#select : Array(Int32)")
    Tango::Compiler::Editor::HoverText.render(map_hover).should eq("Array(Int32)#map : Array(Int32)")
  end
end
