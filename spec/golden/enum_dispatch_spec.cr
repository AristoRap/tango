require "../spec_helper"
require "../../src/tango/dump"

describe "enum declaration and exhaustive dispatch" do
  source_path = File.join("examples", "enum_dispatch.tn")
  source = File.read(source_path)
  snapshot = Tango.snapshot(source, filename: source_path)

  it "preserves nominal declarations and members through every phase" do
    Tango::Dump::NIR.render(snapshot).should contain("Enum State : Int32 { Idle=0, Running=1, Done=2 }")
    Tango::Dump::Facts.render(snapshot).should contain("enum State base=Int32 (Idle=0) (Running=1) (Done=2)")
    Tango::Dump::Plans.render(snapshot).should contain("enum_repr State NominalInteger base=Int32 target=State")

    lir = Tango::Dump::LIR.render(snapshot)
    lir.should contain("Enum State : Int32 (Idle=0 -> State_Idle) (Running=1 -> State_Running) (Done=2 -> State_Done)")
    lir.should contain("EnumConst State::Idle")

    go = expect_present(snapshot.go_source)
    go.should contain("type State int32")
    go.should contain("State_Idle")
    go.should_not contain("interface{}")
  end

  it "keeps Crystal's exhaustive proof and source range at the frontend boundary" do
    incomplete = <<-TN
      enum State
        Idle
        Running
        Done
      end

      def label(state : State) : String
        case state
        in State::Idle
          "idle"
        in State::Running
          "running"
        end
      end

      puts label(State::Idle)
      TN
    failed = Tango.pre_target_snapshot(incomplete, filename: "incomplete_enum.tn")
    diagnostic = failed.diagnostics.first

    diagnostic.message.should contain("case is not exhaustive for enum State")
    diagnostic.message.should contain("Done")
    range = expect_present(diagnostic.range)
    {range.line, range.column}.should eq({8, 3})
  end

  it "navigates and hovers enum types and member values by semantic identity" do
    definition = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, source_path, 20, 19))
    {definition.line, definition.column, definition.size}.should eq({2, 3, 4})

    type_hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 1, 6))
    member_hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 20, 19))
    Tango::Compiler::Editor::HoverText.render(type_hover).should eq("enum State")
    Tango::Compiler::Editor::HoverText.render(member_hover).should eq("State::Idle : State")
  end
end
