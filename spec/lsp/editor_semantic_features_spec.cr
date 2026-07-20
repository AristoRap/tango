require "../spec_helper"
require "../../src/tango/lsp"

module EditorSemanticSpecSupport
  def self.frame(payload) : String
    body = payload.to_json
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def self.run(requests : Array) : Array(JSON::Any)
    input = IO::Memory.new(requests.map { |request| frame(request) }.join)
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

  def self.response(messages : Array(JSON::Any), id : Int32) : JSON::Any
    messages.find! { |message| message["id"]?.try(&.as_i) == id }["result"]
  end

  def self.decode_tokens(data : Array(JSON::Any))
    line = 0
    start = 0
    data.each_slice(5).map do |fields|
      delta_line, delta_start, length, type, modifiers = fields.map(&.as_i)
      line += delta_line
      start = delta_line.zero? ? start + delta_start : delta_start
      {line: line, start: start, length: length, type: type, modifiers: modifiers}
    end.to_a
  end
end

describe "editor semantic features" do
  it "advertises type definition" do
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", id: 1, method: "initialize", params: {} of String => String},
    ])

    capabilities = EditorSemanticSpecSupport.response(messages, 1)["capabilities"]
    capabilities["typeDefinitionProvider"].as_bool.should be_true
    capabilities["inlayHintProvider"].as_bool.should be_true
    semantic = capabilities["semanticTokensProvider"]
    semantic["legend"]["tokenTypes"].as_a.map(&.as_s).should eq(%w(class function method variable parameter property))
    semantic["legend"]["tokenModifiers"].as_a.map(&.as_s).should eq(%w(declaration modification))
    semantic["full"].as_bool.should be_true
  end

  it "returns exact delta-encoded resolved identifiers and mutable writes" do
    uri = "file:///semantic_tokens.tn"
    source = <<-TN
      class Report
        def emit(line : String)
          puts line
        end
      end

      def report(value : String)
        line = value
        line = value
        Report.new.emit(line)
      end

      report "ready"
      TN
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 6, method: "textDocument/semanticTokens/full", params: {textDocument: {uri: uri}}},
    ])

    EditorSemanticSpecSupport.response(messages, 6)["data"].as_a.map(&.as_i).should eq([
      0, 6, 6, 0, 1,
      1, 6, 4, 2, 1,
      0, 5, 4, 4, 1,
      1, 4, 4, 2, 0,
      0, 5, 4, 4, 0,
      4, 4, 6, 1, 1,
      0, 7, 5, 4, 1,
      1, 2, 4, 3, 3,
      0, 7, 5, 4, 0,
      1, 2, 4, 3, 2,
      0, 7, 5, 4, 0,
      1, 2, 6, 0, 0,
      0, 7, 3, 2, 0,
      0, 4, 4, 2, 0,
      0, 5, 4, 3, 0,
      3, 0, 6, 1, 0,
    ])
  end

  it "classifies the weather loop from semantic identities" do
    path = File.expand_path("../../examples/weather_report.tn", __DIR__)
    uri = "file://#{path}"
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: File.read(path), version: 1}}},
      {jsonrpc: "2.0", id: 7, method: "textDocument/semanticTokens/full", params: {textDocument: {uri: uri}}},
    ])

    tokens = EditorSemanticSpecSupport.decode_tokens(EditorSemanticSpecSupport.response(messages, 7)["data"].as_a)
    tokens.select { |token| token[:line].in?(47..51) }.should eq([
      {line: 47, start: 2, length: 13, type: 3, modifiers: 0},
      {line: 47, start: 16, length: 4, type: 2, modifiers: 0},
      {line: 47, start: 21, length: 4, type: 2, modifiers: 0},
      {line: 47, start: 30, length: 7, type: 4, modifiers: 1},
      {line: 48, start: 4, length: 5, type: 3, modifiers: 3},
      {line: 48, start: 12, length: 8, type: 3, modifiers: 0},
      {line: 48, start: 21, length: 7, type: 4, modifiers: 0},
      {line: 49, start: 4, length: 4, type: 3, modifiers: 3},
      {line: 49, start: 13, length: 5, type: 3, modifiers: 0},
      {line: 49, start: 19, length: 3, type: 2, modifiers: 0},
      {line: 49, start: 25, length: 5, type: 3, modifiers: 0},
      {line: 49, start: 31, length: 5, type: 2, modifiers: 0},
      {line: 49, start: 37, length: 4, type: 2, modifiers: 0},
      {line: 49, start: 51, length: 5, type: 2, modifiers: 0},
      {line: 50, start: 4, length: 4, type: 3, modifiers: 3},
      {line: 50, start: 14, length: 7, type: 4, modifiers: 0},
      {line: 50, start: 25, length: 5, type: 3, modifiers: 0},
      {line: 50, start: 31, length: 7, type: 2, modifiers: 0},
      {line: 50, start: 42, length: 4, type: 3, modifiers: 0},
      {line: 50, start: 50, length: 5, type: 3, modifiers: 0},
      {line: 50, start: 56, length: 7, type: 2, modifiers: 0},
      {line: 51, start: 4, length: 4, type: 2, modifiers: 0},
      {line: 51, start: 9, length: 4, type: 3, modifiers: 0},
      {line: 51, start: 17, length: 4, type: 4, modifiers: 0},
    ])
    tokens.should contain({line: 9, start: 5, length: 5, type: 5, modifiers: 2})
  end

  it "retains semantic tokens in unchanged text while editing" do
    uri = "file:///semantic_editing.tn"
    source = "# stable\nvalue = 1\nputs value\n"
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: "\n#{source}"}]}},
      {jsonrpc: "2.0", id: 8, method: "textDocument/semanticTokens/full", params: {textDocument: {uri: uri}}},
    ])

    EditorSemanticSpecSupport.decode_tokens(EditorSemanticSpecSupport.response(messages, 8)["data"].as_a).should eq([
      {line: 2, start: 0, length: 5, type: 3, modifiers: 3},
      {line: 3, start: 0, length: 4, type: 2, modifiers: 0},
      {line: 3, start: 5, length: 5, type: 3, modifiers: 0},
    ])
  end

  it "returns inferred local-type and resolved parameter-name hints" do
    uri = "file:///semantic_hints.tn"
    source = <<-TN
      def record(station : String, temperature : Float64)
        puts station
        puts temperature
      end

      reading = 10.0
      record("AMS", reading)
      temperature : Float64 = 11.0
      record("AMS", temperature)
      TN
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 4, method: "textDocument/inlayHint", params: {textDocument: {uri: uri}, range: {start: {line: 0, character: 0}, end: {line: 8, character: 100}}}},
    ])

    hints = EditorSemanticSpecSupport.response(messages, 4).as_a
    hints.map { |hint| hint["label"].as_s }.should eq([
      ": Float64",
      "station:",
      "temperature:",
      "station:",
    ])
    hints.map { |hint| hint["kind"].as_i }.should eq([1, 2, 2, 2])
    hints[0]["position"]["line"].as_i.should eq(5)
    hints[0]["position"]["character"].as_i.should eq(7)
    hints[1]["position"]["line"].as_i.should eq(6)
    hints[1]["position"]["character"].as_i.should eq(7)
    hints[2]["position"]["character"].as_i.should eq(14)
    hints[3]["position"]["line"].as_i.should eq(8)
    hints[3]["position"]["character"].as_i.should eq(7)
  end

  it "keeps generated Range constructor parameters out of capability call hints" do
    path = File.expand_path("../../examples/capability_dispatch.tn", __DIR__)
    uri = "file://#{path}"
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: File.read(path), version: 1}}},
      {jsonrpc: "2.0", id: 13, method: "textDocument/inlayHint", params: {textDocument: {uri: uri}, range: {start: {line: 13, character: 0}, end: {line: 15, character: 100}}}},
    ])

    hints = EditorSemanticSpecSupport.response(messages, 13).as_a
    hints.map { |hint| hint["label"].as_s }.should eq(["values:", "values:"])
    hints.map { |hint| hint["position"]["line"].as_i }.should eq([13, 14])
    hints.map { |hint| hint["position"]["character"].as_i }.should eq([9, 9])
  end

  it "does not expose generated array-literal temporaries as type hints" do
    path = File.expand_path("../../examples/fused_collection.tn", __DIR__)
    uri = "file://#{path}"
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: File.read(path), version: 1}}},
      {jsonrpc: "2.0", id: 9, method: "textDocument/inlayHint", params: {textDocument: {uri: uri}, range: {start: {line: 0, character: 0}, end: {line: 2, character: 0}}}},
      {jsonrpc: "2.0", id: 10, method: "textDocument/hover", params: {textDocument: {uri: uri}, position: {line: 0, character: 16}}},
      {jsonrpc: "2.0", id: 11, method: "textDocument/hover", params: {textDocument: {uri: uri}, position: {line: 0, character: 2}}},
      {jsonrpc: "2.0", id: 12, method: "textDocument/semanticTokens/full", params: {textDocument: {uri: uri}}},
    ])

    hints = EditorSemanticSpecSupport.response(messages, 9).as_a
    hints.map { |hint| hint["label"].as_s }.should eq([": Array(Int32)"])
    hints.first["position"]["line"].as_i.should eq(0)
    hints.first["position"]["character"].as_i.should eq(6)
    EditorSemanticSpecSupport.response(messages, 10).raw.should be_nil
    EditorSemanticSpecSupport.response(messages, 11)["contents"]["value"].as_s.should eq("values : Array(Int32)")
    tokens = EditorSemanticSpecSupport.decode_tokens(EditorSemanticSpecSupport.response(messages, 12)["data"].as_a)
    tokens.select { |token| token[:line].zero? }.should eq([
      {line: 0, start: 0, length: 6, type: 3, modifiers: 3},
    ])
  end

  it "retains compatible last-good hints while an edit is being analyzed" do
    uri = "file:///semantic_editing.tn"
    source = <<-TN
      def record(station : String, temperature : Float64)
        puts station
        puts temperature
      end

      reading = 10.0
      record("AMS", reading)
      TN
    current = "\n#{source}"
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: current}]}},
      {jsonrpc: "2.0", id: 5, method: "textDocument/inlayHint", params: {textDocument: {uri: uri}, range: {start: {line: 0, character: 0}, end: {line: 7, character: 100}}}},
    ])

    hints = EditorSemanticSpecSupport.response(messages, 5).as_a
    hints.map { |hint| hint["label"].as_s }.should eq([
      ": Float64",
      "station:",
      "temperature:",
    ])
    hints.map { |hint| hint["position"]["line"].as_i }.should eq([6, 7, 7])
  end

  it "navigates from a Unicode-positioned inferred local to its source-declared class" do
    uri = "file:///semantic_type_definition.tn"
    source = <<-TN
      class StationStats
        getter count : Int32

        def initialize(@count : Int32)
        end
      end

      _prefix = "🚀"; stats = StationStats.new(10)
      puts stats.count
      TN
    messages = EditorSemanticSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 2, method: "textDocument/typeDefinition", params: {textDocument: {uri: uri}, position: {line: 7, character: 17}}},
    ])

    location = EditorSemanticSpecSupport.response(messages, 2)
    location["uri"].as_s.should eq(uri)
    location["range"]["start"]["line"].as_i.should eq(0)
    location["range"]["start"]["character"].as_i.should eq(6)
    location["range"]["end"]["character"].as_i.should eq(18)
  end

  it "navigates across the authoritative required-file graph" do
    root = File.join(Dir.tempdir, "tango-type-definition-#{Process.pid}-#{Random.rand(100_000)}")
    Dir.mkdir_p(root)
    support = File.join(root, "station_stats.tn")
    main = File.join(root, "main.tn")
    File.write(support, <<-TN)
      class StationStats
        getter count : Int32

        def initialize(@count : Int32)
        end
      end
      TN
    source = <<-TN
      require "./station_stats"
      stats = StationStats.new(10)
      puts stats.count
      TN
    File.write(main, source)

    begin
      messages = EditorSemanticSpecSupport.run([
        {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file://#{main}", text: source, version: 1}}},
        {jsonrpc: "2.0", id: 3, method: "textDocument/typeDefinition", params: {textDocument: {uri: "file://#{main}"}, position: {line: 2, character: 7}}},
      ])

      location = EditorSemanticSpecSupport.response(messages, 3)
      location["uri"].as_s.should eq("file://#{support}")
      location["range"]["start"]["line"].as_i.should eq(0)
      location["range"]["start"]["character"].as_i.should eq(6)
    ensure
      File.delete(main) if File.exists?(main)
      File.delete(support) if File.exists?(support)
      Dir.delete(root) if Dir.exists?(root)
    end
  end

  it "keeps an exact structured query contract across analysis transport" do
    path = "/virtual/semantic_projected.tn"
    source = <<-TN
      class StationStats
        getter count : Int32

        def initialize(@count : Int32)
        end
      end

      stats = StationStats.new(10)
      puts stats.count
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: path)
    snapshot.diagnostics.should be_empty
    projected = Tango::Lsp::AnalysisCodec.load(Tango::Lsp::AnalysisCodec.dump(snapshot))
    result = Tango::Compiler::Editor::TypeDefinition.at(projected, path, 9, 6)

    target = expect_present(result)
    target.type.should eq(Tango::IR::Type.klass("StationStats"))
    target.target.path.should eq(path)
    target.target.start_offset.should eq(6)
    target.completeness.exact?.should be_true

    tokens = Tango::Compiler::Editor::SemanticTokens.in(projected, path, 0, source.bytesize)
    tokens.completeness.exact?.should be_true
    tokens.tokens.should eq(snapshot.editor_index.semantic_tokens)
  end

  it "rejects built-ins and union declarations but follows exact flow narrowing" do
    path = "/virtual/semantic_exact_only.tn"
    source = <<-TN
      class StationStats
        def count : Int32
          1
        end
      end

      def find(hit : Bool) : StationStats?
        if hit
          StationStats.new
        else
          nil
        end
      end

      count = 1
      stats = find(true)
      puts count
      if stats
        puts stats.count
      end
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: path)
    snapshot.diagnostics.should be_empty

    Tango::Compiler::Editor::TypeDefinition.at(snapshot, path, 17, 6).should be_nil
    Tango::Compiler::Editor::TypeDefinition.at(snapshot, path, 16, 2).should be_nil
    narrowed = expect_present(Tango::Compiler::Editor::TypeDefinition.at(snapshot, path, 19, 8))
    narrowed.type.should eq(Tango::IR::Type.klass("StationStats"))
    narrowed.completeness.exact?.should be_true
  end
end
