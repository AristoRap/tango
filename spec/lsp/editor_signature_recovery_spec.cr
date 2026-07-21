require "../spec_helper"
require "../../src/tango/lsp"

private def recovered_constructor_signature(
  source : String,
  line : Int32,
  character : Int32,
) : Tango::Compiler::Editor::Completion::SignatureResult
  uri = "file:///constructor_signature.tn"
  path = "/constructor_signature.tn"
  workspace = Tango::Lsp::Workspace.new(IO::Memory.new, recovery_limit: 5.seconds)
  document = workspace.open(uri, path, source, 1)
  offset = document.source_line_index.byte_offset_at(line + 1, character + 1)
  context = Tango::Compiler::Editor::Context.at(source, offset)
  recovered = expect_present(Tango::Lsp::RecoveryQuery.at(
    workspace,
    document,
    context,
    context.call_receiver,
    offset
  ))
  expect_present(Tango::Compiler::Editor::Completion.signature_help(
    context,
    recovered.snapshot.syntax_surface,
    recovered.snapshot.editor_index,
    recovered.receiver,
    nil,
    path,
    offset
  ))
ensure
  workspace.try(&.stop)
end

describe "editor constructor signature recovery" do
  it "recovers a signature for a newly typed invalid constructor call" do
    source = <<-TN
      class StationStats
        def initialize(value : Int32)
        end
      end
      StationStats.new(
      TN

    result = recovered_constructor_signature(source, 4, 17)

    result.active_signature.should eq(0)
    result.active_parameter.should eq(0)
    signature = result.signatures.first
    signature.label.should eq("StationStats.new(value : Int32) : StationStats")
    signature.parameters.first.label.should eq("value : Int32")
  end

  it "selects the next constructor parameter after a comma" do
    source = <<-TN
      class StationStats
        def initialize(count : Int32, label : String)
        end
      end
      StationStats.new(10,
      TN

    result = recovered_constructor_signature(source, 4, 21)

    result.active_parameter.should eq(1)
    result.signatures.first.parameters[1].label.should eq("label : String")
  end
end
