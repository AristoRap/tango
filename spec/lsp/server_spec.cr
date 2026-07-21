require "../spec_helper"
require "../../src/tango/lsp"

private def frame(payload) : String
  body = payload.to_json
  "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
end

private def read_frames(io : IO) : Array(JSON::Any)
  messages = [] of JSON::Any
  while message = Tango::Lsp::JsonRpc.read_message(io)
    messages << message
  end
  messages
end

private def run_server(requests : Array) : Array(JSON::Any)
  input = IO::Memory.new(requests.map { |r| frame(r) }.join)
  output = IO::Memory.new
  error = IO::Memory.new

  Tango::Lsp::Server.new(input, output, error).run

  output.rewind
  read_frames(output)
end

private def published_for(responses : Array(JSON::Any), uri : String) : Array(JSON::Any)
  responses.select do |message|
    message["method"]?.try(&.as_s) == "textDocument/publishDiagnostics" &&
      message["params"]["uri"].as_s == uri
  end
end

describe Tango::Lsp::Server do
  it "opens tango/fs without diagnostics and navigates to it from an application" do
    package_path = File.join(Tango::Workspace::Layout.bundled_packages_dir, "tango", "fs.tn")
    app_path = File.expand_path("../../examples/weather_report.tn", __DIR__)
    package_uri = "file://#{package_path}"
    app_uri = "file://#{app_path}"
    package_source = File.read(package_path)
    file_line = package_source.lines.index!(&.includes?("class File"))
    package_read_line = package_source.lines.index!(&.includes?("def self.read"))
    app_source = File.read(app_path)
    read_line = app_source.lines.index!(&.includes?("File.read"))
    read_character = app_source.lines[read_line].index!("File.read")
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: package_uri, text: package_source, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: app_uri, text: app_source, version: 1}}},
      {jsonrpc: "2.0", id: 28, method: "textDocument/definition", params: {textDocument: {uri: app_uri}, position: {line: read_line, character: read_character + 6}}},
      {jsonrpc: "2.0", id: 29, method: "textDocument/definition", params: {textDocument: {uri: app_uri}, position: {line: read_line, character: read_character + 1}}},
      {jsonrpc: "2.0", id: 30, method: "textDocument/hover", params: {textDocument: {uri: app_uri}, position: {line: read_line, character: read_character + 1}}},
      {jsonrpc: "2.0", id: 31, method: "textDocument/hover", params: {textDocument: {uri: app_uri}, position: {line: read_line, character: read_character + 6}}},
    ])

    package_notifications = published_for(responses, package_uri)
    package_notifications.should_not be_empty
    package_notifications.each do |notification|
      notification["params"]["diagnostics"].as_a.should be_empty
    end
    published_for(responses, app_uri).last["params"]["diagnostics"].as_a.should be_empty

    definition = responses.find! { |message| message["id"]?.try(&.as_i) == 28 }["result"]
    definition["uri"].as_s.should eq(package_uri)
    definition["range"]["start"]["line"].as_i.should eq(package_read_line)
    definition["range"]["start"]["character"].as_i.should eq(11)

    receiver_definition = responses.find! { |message| message["id"]?.try(&.as_i) == 29 }["result"]
    receiver_definition["uri"].as_s.should eq(package_uri)
    receiver_definition["range"]["start"]["line"].as_i.should eq(file_line)
    receiver_definition["range"]["start"]["character"].as_i.should eq(6)

    receiver_hover = responses.find! { |message| message["id"]?.try(&.as_i) == 30 }["result"]
    method_hover = responses.find! { |message| message["id"]?.try(&.as_i) == 31 }["result"]
    receiver_hover["contents"]["value"].as_s.should eq("```tango\nclass File\n```")
    method_hover["contents"]["value"].as_s.should eq("```tango\ndef File.read(path : String) : String\n```")
  end

  it "expands unsaved wildcard dependencies through the shared workspace resolver" do
    main_uri = "file:///virtual/glob_main.tn"
    alpha_uri = "file:///virtual/support/alpha.tn"
    zeta_uri = "file:///virtual/support/zeta.tn"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: main_uri, text: "require \"./support/*\"\nputs alpha + zeta\n", version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: zeta_uri, text: "def zeta : Int32\n  2\nend\n", version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: alpha_uri, text: "def alpha : Int32\n  1\nend\n", version: 1}}},
      {jsonrpc: "2.0", id: 6, method: "textDocument/definition", params: {textDocument: {uri: main_uri}, position: {line: 1, character: 5}}},
    ])

    published_for(responses, main_uri).last["params"]["diagnostics"].as_a.should be_empty
    # The request is intentionally adjacent to didOpen: the owning root is
    # still in background analysis, so navigation degrades instead of blocking.
    responses.find! { |message| message["id"]?.try(&.as_i) == 6 }["result"].raw.should be_nil
  end

  it "navigates through the recursive disk graph" do
    main_path = File.expand_path("../../examples/require_graph.tn", __DIR__)
    point_path = File.expand_path("../../examples/support/require_graph/nested/10_point.tn", __DIR__)
    main_uri = "file://#{main_path}"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: main_uri, text: File.read(main_path), version: 1}}},
      {jsonrpc: "2.0", id: 8, method: "textDocument/definition", params: {textDocument: {uri: main_uri}, position: {line: 2, character: 8}}},
    ])

    published_for(responses, main_uri).last["params"]["diagnostics"].as_a.should be_empty
    definition = responses.find! { |message| message["id"]?.try(&.as_i) == 8 }["result"]
    definition["uri"].as_s.should eq("file://#{point_path}")
    definition["range"]["start"]["line"].as_i.should eq(0)
    definition["range"]["start"]["character"].as_i.should eq(6)
  end

  it "hovers inside an open dependency using its owning root graph" do
    main_path = File.expand_path("../../examples/require_graph.tn", __DIR__)
    dependency_path = File.expand_path("../../examples/support/require_graph/nested/20_combined.tn", __DIR__)
    main_uri = "file://#{main_path}"
    dependency_uri = "file://#{dependency_path}"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: main_uri, text: File.read(main_path), version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: dependency_uri, text: File.read(dependency_path), version: 1}}},
      {jsonrpc: "2.0", id: 10, method: "textDocument/hover", params: {textDocument: {uri: dependency_uri}, position: {line: 2, character: 13}}},
      {jsonrpc: "2.0", id: 11, method: "textDocument/hover", params: {textDocument: {uri: dependency_uri}, position: {line: 3, character: 2}}},
      {jsonrpc: "2.0", id: 12, method: "textDocument/hover", params: {textDocument: {uri: dependency_uri}, position: {line: 3, character: 14}}},
    ])

    published_for(responses, dependency_uri).last["params"]["diagnostics"].as_a.should be_empty
    parameter = responses.find! { |message| message["id"]?.try(&.as_i) == 10 }["result"]
    scale = responses.find! { |message| message["id"]?.try(&.as_i) == 11 }["result"]
    sum = responses.find! { |message| message["id"]?.try(&.as_i) == 12 }["result"]
    parameter["contents"]["value"].as_s.should eq("```tango\npoint : Point\n```")
    scale["contents"]["value"].as_s.should contain("def scale(value : Int32) : Int32")
    sum["contents"]["value"].as_s.should contain("def Point#sum : Int32")
  end

  it "resolves an unsaved dependency with the shared local-path contract" do
    dependency_uri = "file:///virtual/dependency.tn"
    main_uri = "file:///virtual/main.tn"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: main_uri, text: "require \"./dependency\"\nputs answer\n", version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: dependency_uri, text: "def answer : Int32\n  7\nend\n", version: 1}}},
      {jsonrpc: "2.0", id: 7, method: "textDocument/definition", params: {textDocument: {uri: main_uri}, position: {line: 1, character: 5}}},
    ])

    main_diagnostics = published_for(responses, main_uri)
    main_diagnostics.first["params"]["diagnostics"].as_a.should_not be_empty
    main_diagnostics.last["params"]["diagnostics"].as_a.should be_empty
    # No compatible semantic graph existed before the overlay opened. The
    # immediate request returns no guess while background analysis catches up.
    responses.find! { |message| message["id"]?.try(&.as_i) == 7 }["result"].raw.should be_nil
  end

  it "recomputes open roots when an unsaved dependency changes" do
    dependency_uri = "file:///virtual/recomputed_dependency.tn"
    main_uri = "file:///virtual/recomputed_main.tn"
    valid = "def answer(value : String) : Int32\n  1\nend\n"
    broken = "def answer(value : String) : Int32\n  value + 1\nend\n"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: dependency_uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: main_uri, text: "require \"./recomputed_dependency\"\nputs answer(\"x\")\n", version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: dependency_uri, version: 2}, contentChanges: [{text: broken}]}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: dependency_uri, version: 3}, contentChanges: [{text: valid}]}},
    ])

    notifications = published_for(responses, dependency_uri)
    notifications.none? do |message|
      message["params"]["version"]?.try(&.as_i) == 2 &&
        !message["params"]["diagnostics"].as_a.empty?
    end.should be_true
    notifications.last["params"]["version"].as_i.should eq(3)
    notifications.last["params"]["diagnostics"].as_a.should be_empty
  end

  it "publishes disk dependency diagnostics and clears them when the edge disappears" do
    fixtures = File.expand_path("../fixtures/source_graph_diagnostics/type_error", __DIR__)
    main_path = File.join(fixtures, "main.tn")
    dependency_path = File.join(fixtures, "dependency.tn")
    main_uri = "file://#{main_path}"
    dependency_uri = "file://#{dependency_path}"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: main_uri, text: File.read(main_path), version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: main_uri, version: 2}, contentChanges: [{text: "puts 1\n"}]}},
    ])

    notifications = published_for(responses, dependency_uri)
    notifications.first["params"]["diagnostics"].as_a.should_not be_empty
    notifications.last["params"]["diagnostics"].as_a.should be_empty
  end

  it "resolves goto-definition into a required file with that file's line index" do
    fixtures = File.expand_path("../fixtures/source_graph_diagnostics/same_offset", __DIR__)
    main_path = File.join(fixtures, "main.tn")
    first_path = File.join(fixtures, "first.tn")
    main_uri = "file://#{main_path}"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: main_uri, text: File.read(main_path), version: 1}}},
      {jsonrpc: "2.0", id: 9, method: "textDocument/definition", params: {textDocument: {uri: main_uri}, position: {line: 3, character: 5}}},
    ])

    definition = responses.find! { |message| message["id"]?.try(&.as_i) == 9 }["result"]
    definition["uri"].as_s.should eq("file://#{first_path}")
    definition["range"]["start"]["line"].as_i.should eq(0)
    definition["range"]["start"]["character"].as_i.should eq(4)
  end

  it "responds to initialize with server capabilities" do
    responses = run_server([{jsonrpc: "2.0", id: 1, method: "initialize", params: {} of String => String}])

    responses.size.should eq(1)
    responses.first["id"].as_i.should eq(1)
    responses.first["result"]["capabilities"]["textDocumentSync"].as_i.should eq(1)
    responses.first["result"]["capabilities"]["documentFormattingProvider"].as_bool.should be_true
  end

  it "formats an open document as one Unicode-aware whole-document edit" do
    uri = "file:///format_unicode.tn"
    source = %(puts "😀"  )
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 20, method: "textDocument/formatting", params: {textDocument: {uri: uri}, options: {tabSize: 8, insertSpaces: false}}},
    ])

    edit = responses.find! { |message| message["id"]?.try(&.as_i) == 20 }["result"].as_a.first
    edit["newText"].as_s.should eq(%(puts "😀"\n))
    edit["range"]["start"]["line"].as_i.should eq(0)
    edit["range"]["start"]["character"].as_i.should eq(0)
    edit["range"]["end"]["line"].as_i.should eq(0)
    edit["range"]["end"]["character"].as_i.should eq(11)
  end

  it "returns no formatting edits for canonical or syntactically invalid documents" do
    clean_uri = "file:///format_clean.tn"
    broken_uri = "file:///format_broken.tn"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: clean_uri, text: "puts(1)\n", version: 1}}},
      {jsonrpc: "2.0", id: 21, method: "textDocument/formatting", params: {textDocument: {uri: clean_uri}, options: {tabSize: 2, insertSpaces: true}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: broken_uri, text: "if", version: 1}}},
      {jsonrpc: "2.0", id: 22, method: "textDocument/formatting", params: {textDocument: {uri: broken_uri}, options: {tabSize: 2, insertSpaces: true}}},
      {jsonrpc: "2.0", id: 23, method: "textDocument/formatting", params: {textDocument: {uri: "file:///unknown.tn"}, options: {tabSize: 2, insertSpaces: true}}},
    ])

    responses.find! { |message| message["id"]?.try(&.as_i) == 21 }["result"].as_a.should be_empty
    responses.find! { |message| message["id"]?.try(&.as_i) == 22 }["result"].raw.should be_nil
    responses.find! { |message| message["id"]?.try(&.as_i) == 23 }["result"].raw.should be_nil
  end

  it "publishes no diagnostics for a clean document" do
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///clean.tn", text: "puts 1"}}},
    ])

    responses.size.should eq(1)
    notification = responses.first
    notification["method"].as_s.should eq("textDocument/publishDiagnostics")
    notification["params"]["diagnostics"].as_a.should be_empty
  end

  it "publishes unused locals as unnecessary diagnostics for editor fading" do
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///unused_local.tn", text: "stale = 7\nputs 1\n"}}},
    ])

    diagnostic = responses.first["params"]["diagnostics"].as_a.first
    diagnostic["code"].as_s.should eq(Tango::Diagnostics::LINT_UNUSED_LOCAL)
    diagnostic["severity"].as_i.should eq(2)
    diagnostic["tags"].as_a.map(&.as_i).should eq([1])
    diagnostic["range"]["start"]["line"].as_i.should eq(0)
    diagnostic["range"]["start"]["character"].as_i.should eq(0)
    diagnostic["range"]["end"]["character"].as_i.should eq(5)
  end

  it "publishes a diagnostic for a broken document" do
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///broken.tn", text: "puts("}}},
    ])

    notification = responses.first
    diagnostics = notification["params"]["diagnostics"].as_a
    diagnostics.should_not be_empty
  end

  it "publishes a missing-require diagnostic on the requested path" do
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///missing_require.tn", text: "require \"./definitely_missing\"\n"}}},
    ])

    range = responses.first["params"]["diagnostics"].as_a.first["range"]
    range["start"]["line"].as_i.should eq(0)
    range["start"]["character"].as_i.should eq(8)
    range["end"]["character"].as_i.should eq(30)
  end

  it "publishes an instantiated type error on the actionable inner expression" do
    source = "class Point\n  def initialize(x : Int32)\n    @x = x\n  end\nend\n\ndef find(hit : Bool) : Point?\n  if hit\n    Point.new(\"7\")\n  else\n    nil\n  end\nend\n\np = find(true)"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///nested_error.tn", text: source}}},
    ])

    diagnostic = responses.first["params"]["diagnostics"].as_a.first
    range = diagnostic["range"]
    range["start"]["line"].as_i.should eq(8)
    range["start"]["character"].as_i.should eq(14)
    range["end"]["character"].as_i.should eq(17)
    diagnostic["message"].as_s.should contain("expected argument #1 to 'Point.new' to be Int32, not String")
    diagnostic["message"].as_s.should_not contain("instantiating")
  end

  it "publishes a nilable return mismatch with the inner return error message" do
    path = File.expand_path("../../examples/nilable.tn", __DIR__)
    source = File.read(path).sub("    5", "    \"5\"")
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file://#{path}", text: source}}},
    ])

    diagnostic = responses.first["params"]["diagnostics"].as_a.first
    range = diagnostic["range"]
    range["start"]["line"].as_i.should eq(0)
    range["start"]["character"].as_i.should eq(24)
    diagnostic["message"].as_s.should contain("must return (Int32 | Nil) but it is returning (String | Nil)")
    diagnostic["message"].as_s.should_not contain("instantiating")
  end

  it "publishes frontend messages without root-qualified free functions" do
    source = "def maybe : Int32?\n  \"x\"\nend\nmaybe\n"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///nilable_return_error.tn", text: source}}},
    ])

    diagnostic = responses.first["params"]["diagnostics"].as_a.first
    diagnostic["message"].as_s.should eq("method maybe must return (Int32 | Nil) but it is returning String")
  end

  it "advertises the definition capability" do
    responses = run_server([{jsonrpc: "2.0", id: 1, method: "initialize", params: {} of String => String}])

    responses.first["result"]["capabilities"]["definitionProvider"].as_bool.should be_true
  end

  it "resolves goto-definition from a call to its def" do
    source = "def add(a : Int32, b : Int32) : Int32\n  a + b\nend\n\nputs add(1, 2)"

    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///def.tn", text: source}}},
      {jsonrpc: "2.0", id: 2, method: "textDocument/definition", params: {textDocument: {uri: "file:///def.tn"}, position: {line: 4, character: 5}}},
    ])

    result = responses.find! { |message| message["id"]?.try(&.as_i) == 2 }["result"]
    result["uri"].as_s.should eq("file:///def.tn")
    result["range"]["start"]["line"].as_i.should eq(0)
    # Lands on the def name `add` (0-based column 4), not the `def` keyword.
    result["range"]["start"]["character"].as_i.should eq(4)
  end

  it "resolves goto-definition from a local read to its declaration" do
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///locals.tn", text: "x = 1\nputs x"}}},
      # `x` in `puts x` — 0-based line 1, character 5 → `x = 1` at line 0, col 0.
      {jsonrpc: "2.0", id: 2, method: "textDocument/definition", params: {textDocument: {uri: "file:///locals.tn"}, position: {line: 1, character: 5}}},
    ])

    result = responses.find! { |message| message["id"]?.try(&.as_i) == 2 }["result"]
    result["uri"].as_s.should eq("file:///locals.tn")
    result["range"]["start"]["line"].as_i.should eq(0)
    result["range"]["start"]["character"].as_i.should eq(0)
  end

  it "returns null goto-definition when the position is not a call" do
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///plain.tn", text: "puts 1"}}},
      {jsonrpc: "2.0", id: 2, method: "textDocument/definition", params: {textDocument: {uri: "file:///plain.tn"}, position: {line: 0, character: 0}}},
    ])

    responses.find! { |message| message["id"]?.try(&.as_i) == 2 }["result"].raw.should be_nil
  end

  it "advertises the hover capability" do
    responses = run_server([{jsonrpc: "2.0", id: 1, method: "initialize", params: {} of String => String}])

    responses.first["result"]["capabilities"]["hoverProvider"].as_bool.should be_true
  end

  it "resolves a `.new` type reference to its class, over the wire" do
    source = "class Point\n  def initialize(x : Int32, y : Int32)\n    @x = x\n    @y = y\n  end\n\n  def x : Int32\n    @x\n  end\nend\n\np = Point.new(1, 2)\nputs p.x"

    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///class.tn", text: source}}},
      # `Point` in `p = Point.new` — 0-based line 11, character 4.
      {jsonrpc: "2.0", id: 2, method: "textDocument/definition", params: {textDocument: {uri: "file:///class.tn"}, position: {line: 11, character: 4}}},
    ])

    result = responses.find! { |message| message["id"]?.try(&.as_i) == 2 }["result"]
    result["range"]["start"]["line"].as_i.should eq(0)
    result["range"]["start"]["character"].as_i.should eq(6) # `class Point` — name at 0-based col 6
  end

  it "hovers an instance-var access as its field type, over the wire" do
    source = "class Point\n  def initialize(x : Int32, y : Int32)\n    @x = x\n    @y = y\n  end\n\n  def x : Int32\n    @x\n  end\nend\n\np = Point.new(1, 2)\nputs p.x"

    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///class.tn", text: source}}},
      # `@x` in `@x = x` — 0-based line 2, character 4.
      {jsonrpc: "2.0", id: 2, method: "textDocument/hover", params: {textDocument: {uri: "file:///class.tn"}, position: {line: 2, character: 4}}},
      {jsonrpc: "2.0", id: 3, method: "textDocument/hover", params: {textDocument: {uri: "file:///class.tn"}, position: {line: 2, character: 5}}},
    ])

    at_sigil = responses.find! { |message| message["id"]?.try(&.as_i) == 2 }["result"]
    at_name = responses.find! { |message| message["id"]?.try(&.as_i) == 3 }["result"]
    at_sigil["contents"]["value"].as_s.should eq("```tango\nx : Int32\n```")
    at_name["contents"]["value"].as_s.should eq("```tango\nx : Int32\n```")
    at_name["range"]["start"]["character"].as_i.should eq(4)
    at_name["range"]["end"]["character"].as_i.should eq(6)
  end

  it "hovers a nilable binding as an explicit union, over the wire" do
    source = "def maybe(hit : Bool) : Int32?\n  if hit\n    5\n  else\n    nil\n  end\nend\n\nx = maybe(true)\n"

    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///nilable_hover.tn", text: source}}},
      # `x` in `x = maybe(true)` — 0-based line 8, character 0.
      {jsonrpc: "2.0", id: 2, method: "textDocument/hover", params: {textDocument: {uri: "file:///nilable_hover.tn"}, position: {line: 8, character: 0}}},
    ])

    result = responses.find! { |message| message["id"]?.try(&.as_i) == 2 }["result"]
    result["contents"]["value"].as_s.should eq("```tango\nx : (Int32 | Nil)\n```")
  end

  it "resolves UTF-16 positions after an astral character through hover and definition" do
    source = "value = 1\nputs \"😀\"; puts value\n"
    responses = run_server([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: "file:///unicode_position.tn", text: source}}},
      # `value` after 😀 begins at UTF-16 character 16 on line 1.
      {jsonrpc: "2.0", id: 2, method: "textDocument/hover", params: {textDocument: {uri: "file:///unicode_position.tn"}, position: {line: 1, character: 16}}},
      {jsonrpc: "2.0", id: 3, method: "textDocument/definition", params: {textDocument: {uri: "file:///unicode_position.tn"}, position: {line: 1, character: 16}}},
    ])

    hover = responses.find! { |message| message["id"]?.try(&.as_i) == 2 }["result"]
    hover["contents"]["value"].as_s.should eq("```tango\nvalue : Int32\n```")

    definition = responses.find! { |message| message["id"]?.try(&.as_i) == 3 }["result"]
    definition["range"]["start"]["line"].as_i.should eq(0)
    definition["range"]["start"]["character"].as_i.should eq(0)
  end
end
