require "../spec_helper"
require "../../src/tango/lsp"

module EditorRecoverySpecSupport
  def self.frame(payload) : String
    body = payload.to_json
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def self.run(requests : Array) : Array(JSON::Any)
    input = IO::Memory.new(requests.map { |request| frame(request) }.join)
    output = IO::Memory.new
    errors = IO::Memory.new
    Tango::Lsp::Server.new(input, output, errors).run
    errors.rewind
    error_text = errors.gets_to_end
    raise error_text unless error_text.empty?
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

  def self.published(messages : Array(JSON::Any), uri : String) : Array(JSON::Any)
    messages.select do |message|
      message["method"]?.try(&.as_s) == "textDocument/publishDiagnostics" &&
        message["params"]["uri"].as_s == uri
    end
  end
end

describe "editor recovery queries" do
  it "returns File.read signature help from a direct invalid open with no last-good snapshot" do
    uri = "file:///virtual/recovery_file_read.tn"
    source = "require \"tango/fs\"\nFile.read(\n"
    messages = EditorRecoverySpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp", params: {textDocument: {uri: uri}, position: {line: 1, character: 10}}},
    ])

    result = EditorRecoverySpecSupport.response(messages, 1)
    result["signatures"].as_a.first["label"].as_s.should eq("File.read(path : String) : String")
    result["activeParameter"].as_i.should eq(0)
  end

  it "recovers a fresh chained receiver fact without installing shadow diagnostics" do
    uri = "file:///virtual/recovery_chain.tn"
    source = <<-TANGO
      class Child
        def name : String
          "child"
        end
      end

      class Box
        def child : Child
          Child.new
        end
      end

      box = Box.new
      box.child.
      TANGO
    messages = EditorRecoverySpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 7}}},
      {jsonrpc: "2.0", id: 2, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 13, character: 10}}},
    ])

    completion = EditorRecoverySpecSupport.response(messages, 2)
    completion["isIncomplete"].as_bool.should be_false
    completion["items"].as_a.map { |item| item["label"].as_s }.should contain("name")
    published = EditorRecoverySpecSupport.published(messages, uri)
    published.all? { |message| message["params"]["version"].as_i == 7 }.should be_true
    published.none? do |message|
      message["params"]["diagnostics"].as_a.any? do |diagnostic|
        diagnostic["message"].as_s.includes?("shadow")
      end
    end.should be_true
  end

  it "keeps recovery fact-only and within the explicit 750ms budget" do
    uri = "file:///virtual/recovery_budget.tn"
    path = "/virtual/recovery_budget.tn"
    source = "require \"tango/fs\"\nFile.read(\n"
    workspace = Tango::Lsp::Workspace.new(IO::Memory.new)
    document = workspace.open(uri, path, source, 1)
    offset = expect_present(source.index("\n")) + 11
    context = Tango::Compiler::Editor::Context.at(source, offset)

    result = Tango::Lsp::RecoveryQuery.at(workspace, document, context, context.call_receiver, offset)

    result.should_not be_nil
    recovered = expect_present(result)
    recovered.shadow.should be_true
    recovered.elapsed.should be < Tango::Lsp::AnalysisWorker::DEFAULT_RECOVERY_LIMIT
    document.semantic_snapshot.should be_nil
    document.snapshot.diagnostics.should_not be_empty
  ensure
    workspace.try(&.stop)
  end

  it "invalidates exactly the root owning an unsaved dependency" do
    dependency_uri = "file:///virtual/recovery_dependency.tn"
    root_uri = "file:///virtual/recovery_main.tn"
    second_root_uri = "file:///virtual/recovery_second_main.tn"
    unrelated_uri = "file:///virtual/recovery_unrelated.tn"
    workspace = Tango::Lsp::Workspace.new(IO::Memory.new, debounce: Time::Span.zero)
    workspace.open(dependency_uri, "/virtual/recovery_dependency.tn", "def answer : Int32\n  1\nend\n", 1)
    workspace.open(root_uri, "/virtual/recovery_main.tn", "require \"./recovery_dependency\"\nputs answer\n", 1)
    workspace.open(second_root_uri, "/virtual/recovery_second_main.tn", "require \"./recovery_dependency\"\nputs answer\n", 1)
    workspace.open(unrelated_uri, "/virtual/recovery_unrelated.tn", "puts 9\n", 1)
    workspace.analysis_requests.clear

    workspace.change(dependency_uri, "/virtual/recovery_dependency.tn", "def answer : Int32\n  2\nend\n", 2)
    workspace.drain

    workspace.analysis_requests.map(&.root_uri).sort.should eq([root_uri, second_root_uri].sort)
    root = expect_present(workspace.document?(root_uri))
    unrelated = expect_present(workspace.document?(unrelated_uri))
    root.analysis_revision.should eq(workspace.revision)
    expect_present(workspace.document?(second_root_uri)).analysis_revision.should eq(workspace.revision)
    unrelated.analysis_revision.should_not eq(workspace.revision)
    semantic = expect_present(root.semantic_snapshot)
    main_file = expect_present(semantic.source.file?("/virtual/recovery_main.tn"))
    offset = expect_present(main_file.code.index("answer\n"))
    semantic.editor_index.symbol_at("/virtual/recovery_main.tn", offset).should_not be_nil
  ensure
    workspace.try(&.stop)
  end

  it "debounces rapid edits and publishes diagnostics only with current document versions" do
    uri = "file:///virtual/recovery_stress.tn"
    valid = "def answer(value : Int32) : Int32\n  value\nend\nputs answer(1)\n"
    broken = valid.sub("answer(1)", "answer(\"old\")")
    messages = EditorRecoverySpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: broken}]}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 3}, contentChanges: [{text: valid}]}},
      {jsonrpc: "2.0", id: 3, method: "textDocument/hover", params: {textDocument: {uri: uri}, position: {line: 3, character: 7}}},
    ])

    EditorRecoverySpecSupport.response(messages, 3)["contents"]["value"].as_s.should contain("answer")
    publications = EditorRecoverySpecSupport.published(messages, uri)
    publications.map { |message| message["params"]["version"].as_i }.should contain(3)
    publications.none? do |message|
      message["params"]["version"].as_i == 2 && !message["params"]["diagnostics"].as_a.empty?
    end.should be_true
    publications.last["params"]["version"].as_i.should eq(3)
    publications.last["params"]["diagnostics"].as_a.should be_empty
    response_index = messages.index! { |message| message["id"]?.try(&.as_i) == 3 }
    final_publication_index = messages.rindex! do |message|
      message["method"]?.try(&.as_s) == "textDocument/publishDiagnostics" &&
        message["params"]["uri"].as_s == uri
    end
    response_index.should be < final_publication_index
  end

  it "terminates an active superseded analysis and restarts at the newest generation" do
    uri = "file:///virtual/recovery_cancel.tn"
    path = "/virtual/recovery_cancel.tn"
    workspace = Tango::Lsp::Workspace.new(IO::Memory.new, debounce: Time::Span.zero)
    workspace.open(uri, path, "puts 1\n", 1)
    slow = String.build do |source|
      600.times do |index|
        source << "def value_#{index} : Int32\n  #{index}\nend\n"
      end
      source << "puts value_599\n"
    end
    workspace.change(uri, path, slow, 2)
    deadline = Time.instant + 1.second
    until workspace.worker.active?(uri) || Time.instant >= deadline
      sleep 1.millisecond
    end
    workspace.worker.active?(uri).should be_true

    workspace.change(uri, path, "puts 3\n", 3)
    workspace.drain

    workspace.worker.cancelled_results.should be >= 1
    current = expect_present(workspace.document?(uri))
    current.analysis_revision.should eq(workspace.revision)
    current.snapshot.diagnostics.should be_empty
  ensure
    workspace.try(&.stop)
  end

  it "round-trips semantic editor facts without retaining compiler IR" do
    path = "/virtual/recovery_codec.tn"
    dependency = "/virtual/recovery_codec_dependency.tn"
    source = "require \"./recovery_codec_dependency\"\nvalue = answer\nputs value\n"
    resolver = Tango::Frontend::SourceGraph.resolver({dependency => "def answer : Int32\n  1\nend\n"})
    snapshot = Tango.pre_target_snapshot(source, filename: path, resolver: resolver)
    restored = Tango::Lsp::AnalysisCodec.load(Tango::Lsp::AnalysisCodec.dump(snapshot))

    restored.semantic_ready?.should be_true
    restored.nir.should be_nil
    restored.facts.should be_nil
    restored.source.requires.size.should eq(1)
    restored.source.edges.first.to.should eq(dependency)
    restored.editor_index.receiver_at(path, expect_present(source.index("value\n"))).should_not be_nil
    symbol = restored.editor_index.symbol_at(path, expect_present(source.rindex("value")))
    restored.editor_index.occurrences(expect_present(symbol)).size.should eq(2)
  end
end
