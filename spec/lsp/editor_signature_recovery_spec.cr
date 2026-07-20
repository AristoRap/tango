require "../spec_helper"
require "../../src/tango/lsp"

private def signature_recovery_frame(payload) : String
  body = payload.to_json
  "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
end

private def signature_recovery_run(requests : Array) : Array(JSON::Any)
  input = IO::Memory.new(requests.map { |request| signature_recovery_frame(request) }.join)
  output = IO::Memory.new
  errors = IO::Memory.new
  Tango::Lsp::Server.new(input, output, errors).run
  errors.to_s.should be_empty

  output.rewind
  messages = [] of JSON::Any
  while message = Tango::Lsp::JsonRpc.read_message(output)
    messages << message
  end
  messages
end

private def signature_recovery_response(messages : Array(JSON::Any), id : Int32) : JSON::Any
  messages.find! { |message| message["id"]?.try(&.as_i) == id }["result"]
end

describe "editor constructor signature recovery" do
  it "returns a signature for a newly typed invalid constructor call" do
    uri = "file:///constructor_signature.tn"
    source = <<-TN
      class StationStats
        def initialize(value : Int32)
        end
      end
      StationStats.new(
      TN
    messages = signature_recovery_run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp", params: {textDocument: {uri: uri}, position: {line: 4, character: 17}, context: {triggerKind: 2, triggerCharacter: "(", isRetrigger: false}}},
    ])

    result = signature_recovery_response(messages, 1)
    result["activeSignature"].as_i.should eq(0)
    result["activeParameter"].as_i.should eq(0)
    signature = result["signatures"].as_a.first
    signature["label"].as_s.should eq("StationStats.new(value : Int32) : StationStats")
    signature["parameters"].as_a.first["label"].as_s.should eq("value : Int32")
  end

  it "highlights the next constructor parameter after a comma" do
    uri = "file:///constructor_second_parameter.tn"
    source = <<-TN
      class StationStats
        def initialize(count : Int32, label : String)
        end
      end
      StationStats.new(10, 
      TN
    messages = signature_recovery_run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 2, method: "textDocument/signatureHelp", params: {textDocument: {uri: uri}, position: {line: 4, character: 21}, context: {triggerKind: 2, triggerCharacter: ",", isRetrigger: true}}},
    ])

    result = signature_recovery_response(messages, 2)
    result["activeParameter"].as_i.should eq(1)
    result["signatures"].as_a.first["parameters"].as_a[1]["label"].as_s.should eq("label : String")
  end
end
