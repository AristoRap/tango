require "../spec_helper"
require "../../src/tango/lsp"

private def refactoring_frame(payload) : String
  body = payload.to_json
  "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
end

private def refactoring_run_server(requests : Array) : Array(JSON::Any)
  input = IO::Memory.new(requests.map { |request| refactoring_frame(request) }.join)
  output = IO::Memory.new
  error = IO::Memory.new
  Tango::Lsp::Server.new(input, output, error).run
  error.to_s.should be_empty

  output.rewind
  messages = [] of JSON::Any
  while message = Tango::Lsp::JsonRpc.read_message(output)
    messages << message
  end
  messages
end

private def refactoring_response(messages : Array(JSON::Any), id : Int32) : JSON::Any
  messages.find! { |message| message["id"]?.try(&.as_i) == id }["result"]
end

private def refactoring_published_diagnostic(messages : Array(JSON::Any), uri : String) : JSON::Any
  messages.find! do |message|
    message["method"]?.try(&.as_s) == "textDocument/publishDiagnostics" &&
      message["params"]["uri"].as_s == uri &&
      !message["params"]["diagnostics"].as_a.empty?
  end["params"]["diagnostics"].as_a.first
end

private def refactoring_code_action_request(id : Int32, uri : String, diagnostic : JSON::Any) : JSON::Any
  JSON.parse({
    jsonrpc: "2.0",
    id:      id,
    method:  "textDocument/codeAction",
    params:  {
      textDocument: {uri: uri},
      range:        diagnostic["range"],
      context:      {diagnostics: [diagnostic]},
    },
  }.to_json)
end

describe "editor refactoring and code actions" do
  it "advertises prepared rename and structured quick fixes" do
    messages = refactoring_run_server([
      {jsonrpc: "2.0", id: 1, method: "initialize", params: {} of String => String},
    ])

    capabilities = refactoring_response(messages, 1)["capabilities"]
    capabilities["renameProvider"]["prepareProvider"].as_bool.should be_true
    capabilities["codeActionProvider"]["codeActionKinds"].as_a.map(&.as_s).should eq(["quickfix"])
  end

  it "renames one Unicode-positioned local identity without touching an unrelated local" do
    uri = "file:///refactoring_unicode_local.tn"
    source = <<-TN
      prefix = "🚀"; value = 1
      puts value
      def other : Int32
        value = 2
        value
      end
      puts other
      TN
    messages = refactoring_run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 4}}},
      {jsonrpc: "2.0", id: 2, method: "textDocument/prepareRename", params: {textDocument: {uri: uri}, position: {line: 0, character: 16}}},
      {jsonrpc: "2.0", id: 3, method: "textDocument/rename", params: {textDocument: {uri: uri}, position: {line: 0, character: 16}, newName: "total"}},
    ])

    preparation = refactoring_response(messages, 2)
    preparation["placeholder"].as_s.should eq("value")
    preparation["range"]["start"]["character"].as_i.should eq(15)

    changes = refactoring_response(messages, 3)["documentChanges"].as_a
    changes.size.should eq(1)
    changes.first["textDocument"]["version"].as_i.should eq(4)
    edits = changes.first["edits"].as_a
    edits.size.should eq(2)
    edits.map { |edit| edit["newText"].as_s }.should eq(["total", "total"])
    edits.map { |edit| edit["range"]["start"]["line"].as_i }.should eq([0, 1])
  end

  it "renames a cross-file overload family without touching a same-named method" do
    root = File.join(Dir.tempdir, "tango-refactoring-cross-file-#{Process.pid}-#{Random.rand(100_000)}")
    Dir.mkdir_p(root)
    support = File.join(root, "support.tn")
    main = File.join(root, "main.tn")
    File.write(support, <<-TN)
      def counter(value : Int32) : Int32
        value + 1
      end

      def counter(value : String) : String
        value
      end

      def reserved(value : String) : String
        value
      end

      class Other
        def counter(value : Int32) : Int32
          value
        end
      end
      TN
    source = <<-TN
      require "./support"
      puts counter(1)
      puts Other.new.counter(2)
      TN
    File.write(main, source)
    uri = "file://#{main}"

    begin
      messages = refactoring_run_server([
        {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 2}}},
        {jsonrpc: "2.0", id: 4, method: "textDocument/rename", params: {textDocument: {uri: uri}, position: {line: 1, character: 7}, newName: "increment"}},
        {jsonrpc: "2.0", id: 15, method: "textDocument/rename", params: {textDocument: {uri: uri}, position: {line: 1, character: 7}, newName: "reserved"}},
      ])

      changes = refactoring_response(messages, 4)["documentChanges"].as_a
      changes.map { |change| change["textDocument"]["uri"].as_s }.should eq(["file://#{main}", "file://#{support}"])
      changes[0]["edits"].as_a.size.should eq(1)
      changes[1]["edits"].as_a.size.should eq(2)
      changes.flat_map { |change| change["edits"].as_a }.all? { |edit| edit["newText"].as_s == "increment" }.should be_true
      refactoring_response(messages, 15).raw.should be_nil
    ensure
      File.delete(main) if File.exists?(main)
      File.delete(support) if File.exists?(support)
      Dir.delete(root) if Dir.exists?(root)
    end
  end

  it "renames a generated property family and preserves field sigils" do
    uri = "file:///refactoring_property.tn"
    source = <<-TN
      class Settings
        property count : Int32 = 1
        def bump
          @count += 1
        end
      end
      settings = Settings.new
      settings.bump
      puts settings.count
      settings.count = 3
      TN
    messages = refactoring_run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 3}}},
      {jsonrpc: "2.0", id: 5, method: "textDocument/rename", params: {textDocument: {uri: uri}, position: {line: 8, character: 16}, newName: "total"}},
    ])

    edits = refactoring_response(messages, 5)["documentChanges"].as_a.first["edits"].as_a
    edits.size.should eq(4)
    edits.map { |edit| edit["newText"].as_s }.should eq(["total", "@total", "total", "total"])
  end

  it "rejects collisions, invalid identifiers, and constructor families" do
    uri = "file:///refactoring_rejections.tn"
    source = <<-TN
      class Pair
        property left : Int32 = 1
        property right : Int32 = 2
      end
      pair = Pair.new
      puts pair.left
      first = 1
      second = 2
      puts first + second
      TN
    messages = refactoring_run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 6, method: "textDocument/rename", params: {textDocument: {uri: uri}, position: {line: 5, character: 12}, newName: "right"}},
      {jsonrpc: "2.0", id: 7, method: "textDocument/rename", params: {textDocument: {uri: uri}, position: {line: 5, character: 12}, newName: "class"}},
      {jsonrpc: "2.0", id: 8, method: "textDocument/prepareRename", params: {textDocument: {uri: uri}, position: {line: 4, character: 13}}},
      {jsonrpc: "2.0", id: 14, method: "textDocument/rename", params: {textDocument: {uri: uri}, position: {line: 8, character: 7}, newName: "second"}},
      {jsonrpc: "2.0", id: 16, method: "textDocument/prepareRename", params: {textDocument: {uri: uri}, position: {line: 0, character: 7}}},
    ])

    refactoring_response(messages, 6).raw.should be_nil
    refactoring_response(messages, 7).raw.should be_nil
    refactoring_response(messages, 8).raw.should be_nil
    refactoring_response(messages, 14).raw.should be_nil
    refactoring_response(messages, 16).raw.should be_nil
  end

  it "rejects rename from bundled read-only declarations and stale semantic text" do
    library_uri = "file:///refactoring_library.tn"
    stale_uri = "file:///refactoring_stale.tn"
    messages = refactoring_run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: library_uri, text: "require \"tango/fs\"\nputs File.read(\"x\")\n", version: 1}}},
      {jsonrpc: "2.0", id: 9, method: "textDocument/prepareRename", params: {textDocument: {uri: library_uri}, position: {line: 1, character: 11}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: stale_uri, text: "value = 1\nputs value\n", version: 1}}},
      {jsonrpc: "2.0", id: 90, method: "textDocument/semanticTokens/full", params: {textDocument: {uri: stale_uri}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: stale_uri, version: 2}, contentChanges: [{text: "# changed\nvalue = 1\nputs value\n"}]}},
      {jsonrpc: "2.0", id: 10, method: "textDocument/rename", params: {textDocument: {uri: stale_uri}, position: {line: 2, character: 7}, newName: "total"}},
    ])

    refactoring_response(messages, 9).raw.should be_nil
    refactoring_response(messages, 10).raw.should be_nil
  end

  it "offers only the exact current structured unused-local fix" do
    uri = "file:///refactoring_fix.tn"
    source = "stale = 7\nputs 1\n"
    first = refactoring_run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 7}}},
    ])
    diagnostic = refactoring_published_diagnostic(first, uri)
    diagnostic["data"]["kind"].as_s.should eq("PrefixUnusedLocal")
    diagnostic["data"]["documentVersion"].as_i.should eq(7)

    request = refactoring_code_action_request(11, uri, diagnostic)
    forged = JSON.parse(diagnostic.to_json.sub(%("newText":"_stale"), %("newText":"danger")))
    forged_request = refactoring_code_action_request(13, uri, forged)
    current = refactoring_run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 7}}},
      request,
      forged_request,
    ])

    actions = refactoring_response(current, 11).as_a
    actions.size.should eq(1)
    actions.first["kind"].as_s.should eq("quickfix")
    edit = actions.first["edit"]["documentChanges"].as_a.first
    edit["textDocument"]["version"].as_i.should eq(7)
    edit["edits"].as_a.first["newText"].as_s.should eq("_stale")
    refactoring_response(current, 13).as_a.should be_empty

    stale_request = refactoring_code_action_request(12, uri, diagnostic)
    rejected = refactoring_run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 8}}},
      stale_request,
    ])

    refactoring_response(rejected, 12).as_a.should be_empty
  end

  it "rebuilds symbol families and structured fixes after process transport" do
    path = "/virtual/refactoring_codec.tn"
    source = <<-TN
      class Settings
        property count : Int32 = 1
      end
      settings = Settings.new
      puts settings.count
      settings.count = 2
      stale = 7
      TN
    restored = Tango::Lsp::AnalysisCodec.load(
      Tango::Lsp::AnalysisCodec.dump(Tango.pre_target_snapshot(source, filename: path))
    )

    restored.nir.should be_nil
    offset = expect_present(source.rindex("count"))
    symbol = expect_present(restored.editor_index.symbol_at(path, offset))
    family = expect_present(restored.editor_index.symbol_family(symbol))
    family.kind.accessor?.should be_true
    family.symbols.size.should eq(3)
    plan = expect_present(Tango::Compiler::Editor::Rename.plan(restored, path, offset, "total"))
    plan.edits.map(&.new_text).should eq(["total", "total", "total"])
    fix = expect_present(restored.diagnostics.find!(&.code.==(Tango::Diagnostics::LINT_UNUSED_LOCAL)).fix)
    fix.kind.prefix_unused_local?.should be_true
    fix.edits.first.new_text.should eq("_stale")
  end
end
