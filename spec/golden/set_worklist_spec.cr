require "../spec_helper"
require "../../src/tango/dump"

describe "typed Set and deterministic worklists" do
  source_path = File.join("examples", "set_worklist.tn")
  source = File.read(source_path)
  snapshot = Tango.snapshot(source, filename: source_path)

  it "composes existing ordered Hash operations through every phase" do
    nir = Tango::Dump::NIR.render(snapshot)
    nir.should contain("Class Set { entries : Hash(Int32, Bool) }")
    nir.should contain("Def Set(Int32)#add? : Bool")
    nir.should contain("Def Set(Int32)#<< : Set(Int32)")
    nir.should contain("Def Set(Int32)#includes? : Bool")
    nir.should contain("HashHasKey Int32, Bool")
    nir.should contain("HashSet Int32, Bool")
    nir.should contain("HashKeyAt Int32, Bool")

    facts = Tango::Dump::Facts.render(snapshot)
    facts.should contain("Set(Int32) struct_layout reference entries : Hash(Int32, Bool)")
    facts.should contain("Hash(Int32, Bool) comparability WrongSemantics")

    plans = Tango::Dump::Plans.render(snapshot)
    plans.should contain("Hash(Int32, Bool) hash_repr Reference order=Insertion")
    plans.should contain("constructor Set__new ->")

    lir = Tango::Dump::LIR.render(snapshot)
    lir.should contain("Struct Setu28_Int32u29_ (entries : Hash(Int32, Bool))")
    lir.should contain("Hash Hash(Int32, Bool) key=Int32 value=Bool repr=Reference order=Insertion")
    lir.should contain("Func addu3f__Setu28_Int32u29__Int32")
    lir.should contain("Func u3c_u3c__Setu28_Int32u29__Int32")
    lir.should contain("Func includesu3f__Setu28_Int32u29__Int32")
    lir.should contain("HashHasKey Int32, Bool")
    lir.should contain("HashSet Int32, Bool")
    lir.should contain("HashKeyAt Int32, Bool")
  end

  it "spells no Set-specific target representation or runtime helper" do
    go = expect_present(snapshot.go_source)
    go.should contain("type Setu28_Int32u29_ struct")
    go.should contain("entries *tangoHash[int32, bool]")
    go.should contain("func addu3f__Setu28_Int32u29__Int32")
    go.should contain("func u3c_u3c__Setu28_Int32u29__Int32")
    go.should contain("func includesu3f__Setu28_Int32u29__Int32")
    go.should contain("tangoHashHas(self.entries, value)")
    go.should contain("tangoHashSet(self.entries, value, true)")
    go.should contain("self.entries.keys[index]")
    go.should_not contain("tangoSet")
    go.should_not contain("range self.entries.m")
  end

  it "retains structured editor local types and resolved Set methods" do
    type_hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 10, 1))
    add_hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 16, 11))

    Tango::Compiler::Editor::HoverText.render(type_hover).should eq("seen : Set(Int32)")
    Tango::Compiler::Editor::HoverText.render(add_hover).should eq("Set(Int32)#add?(Int32) : Bool")
  end
end
