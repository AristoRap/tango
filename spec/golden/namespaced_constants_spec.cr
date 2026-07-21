require "../spec_helper"
require "../../src/tango/dump"

describe "namespaces, constants, and aliases" do
  source_path = File.join("examples", "namespaced_constants.tn")
  source = File.read(source_path)
  snapshot = Tango.snapshot(source, filename: source_path)

  it "preserves declaration ownership through every phase" do
    nir = Tango::Dump::NIR.render(snapshot)
    nir.should contain("Namespace Compiler::Codes")
    nir.should contain("TypeAlias Compiler::Codes::Code = Int32")
    nir.should contain("TypeAliasReference Compiler::Codes::Code = Int32")
    nir.should contain("Constant Compiler::Codes::TABLE : Hash(String, Int32)")
    nir.should contain("ConstantReference Compiler::Codes::TABLE")

    facts = Tango::Dump::Facts.render(snapshot)
    facts.should contain("namespace Compiler::Codes parent=Compiler")
    facts.should contain("constant Compiler::Codes::TABLE : Hash(String, Int32)")
    facts.should contain("type_alias Compiler::Codes::Code = Int32")
    facts.should contain("type_alias_ref Compiler::Codes::Code")
    facts.should contain("constant_ref Compiler::Codes::TABLE")

    plans = Tango::Dump::Plans.render(snapshot)
    plans.should contain("namespace Compiler::Codes target=Compiler_Codes")
    plans.should contain("constant Compiler::Codes::TABLE target=Compiler_Codes_TABLE")

    lir = Tango::Dump::LIR.render(snapshot)
    lir.should contain("Global Compiler_Codes_TABLE : Hash(String, Int32)")
    lir.should contain("GlobalRef Compiler_Codes_TABLE")

    go = expect_present(snapshot.go_source)
    go.should contain("var Compiler_Codes_TABLE *tangoHash[string, int32]")
    go.should contain("tangoHashGet(Compiler_Codes_TABLE, name)")
  end

  it "navigates and hovers constant declarations by semantic identity" do
    definition = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, source_path, 15, 23))
    {definition.line, definition.column, definition.size}.should eq({6, 5, 6})

    constant_hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 15, 23))
    alias_hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 3, 11))
    Tango::Compiler::Editor::HoverText.render(constant_hover).should eq("const PREFIX : String")
    Tango::Compiler::Editor::HoverText.render(alias_hover).should eq("alias Code = Int32")
    Tango::Compiler::Editor::HoverMarkdown.render(constant_hover).should contain("const PREFIX : String")
    Tango::Compiler::Editor::HoverMarkdown.render(alias_hover).should contain("alias Code = Int32")

    return_alias = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 11, 48))
    Tango::Compiler::Editor::HoverMarkdown.render(return_alias).should contain("alias Code = Int32")
  end

  it "includes segmented module ownership in callable target identities" do
    nested = Tango.snapshot(<<-TN, filename: "nested_callable.tn")
      module Compiler
        module Codes
          def self.lookup(value : Int32) : Int32
            value
          end
        end
      end

      puts Compiler::Codes.lookup(3)
      TN
    plans = Tango::Dump::Plans.render(nested)
    plans.should contain("def Compiler_Codes_lookup_Int32")
    plans.should contain("call InternalCall Compiler_Codes_lookup_Int32")
  end
end
