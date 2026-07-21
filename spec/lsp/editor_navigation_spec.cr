require "../spec_helper"
require "../../src/tango/lsp"

module EditorNavigationSpecSupport
  def self.frame(payload) : String
    body = payload.to_json
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def self.run(requests : Array) : Array(JSON::Any)
    input = IO::Memory.new(requests.map { |request| frame(request) }.join)
    output = IO::Memory.new
    Tango::Lsp::Server.new(input, output, IO::Memory.new).run
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

describe "editor navigation and symbols" do
  it "indexes an unused typed method for document and workspace symbols" do
    uri = "file:///virtual/navigation_surface.tn"
    source = <<-TANGO
      class Ledger
        # Current balance.
        def balance(scale : Int32) : Int32
          scale
        end
      end

      puts 1
      TANGO
    messages = EditorNavigationSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 1, method: "textDocument/documentSymbol", params: {textDocument: {uri: uri}}},
      {jsonrpc: "2.0", id: 2, method: "workspace/symbol", params: {query: "bal"}},
    ])

    document_symbols = EditorNavigationSpecSupport.response(messages, 1).as_a
    document_symbols.map { |symbol| symbol["name"].as_s }.should eq(["Ledger", "balance"])
    balance = document_symbols.last
    balance["containerName"].as_s.should eq("Ledger")
    balance["location"]["range"]["start"]["line"].as_i.should eq(2)
    balance["location"]["range"]["start"]["character"].as_i.should eq(6)

    workspace_symbols = EditorNavigationSpecSupport.response(messages, 2).as_a
    workspace_symbols.size.should eq(1)
    workspace_symbols.first["name"].as_s.should eq("balance")
    workspace_symbols.first["location"]["uri"].as_s.should eq(uri)
  end

  it "retains navigation through an unchanged region of a malformed edit" do
    uri = "file:///virtual/navigation_last_good.tn"
    valid = "def answer(value : Int32) : Int32\n  value\nend\n\nputs answer(1)\n"
    broken = valid + "puts(\n"
    changed_token = broken.sub("answer(1)", "ansXYZwer(1)")
    messages = EditorNavigationSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: broken}]}},
      {jsonrpc: "2.0", id: 3, method: "textDocument/definition", params: {textDocument: {uri: uri}, position: {line: 4, character: 7}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 3}, contentChanges: [{text: changed_token}]}},
      {jsonrpc: "2.0", id: 4, method: "textDocument/definition", params: {textDocument: {uri: uri}, position: {line: 4, character: 8}}},
    ])

    diagnostics = EditorNavigationSpecSupport.published(messages, uri)
    diagnostics[1]["params"]["diagnostics"].as_a.should_not be_empty
    retained = EditorNavigationSpecSupport.response(messages, 3)
    retained["range"]["start"]["line"].as_i.should eq(0)
    retained["range"]["start"]["character"].as_i.should eq(4)
    EditorNavigationSpecSupport.response(messages, 4).raw.should be_nil
  end

  it "returns only identity-linked references and document highlights" do
    uri = "file:///virtual/navigation_collisions.tn"
    source = <<-TANGO
      def left : Int32
        value = 1
        puts value
        value
      end

      def right : Int32
        value = 2
        puts value
        value
      end

      puts left + right
      TANGO
    messages = EditorNavigationSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 5, method: "textDocument/references", params: {textDocument: {uri: uri}, position: {line: 2, character: 7}, context: {includeDeclaration: true}}},
      {jsonrpc: "2.0", id: 6, method: "textDocument/documentHighlight", params: {textDocument: {uri: uri}, position: {line: 2, character: 7}}},
    ])

    references = EditorNavigationSpecSupport.response(messages, 5).as_a
    references.map { |location| location["range"]["start"]["line"].as_i }.should eq([1, 2, 3])
    highlights = EditorNavigationSpecSupport.response(messages, 6).as_a
    highlights.map { |highlight| highlight["range"]["start"]["line"].as_i }.should eq([1, 2, 3])
    highlights.all? { |highlight| highlight["kind"].as_i == 1 }.should be_true
  end

  it "returns exact references across a source graph" do
    dependency_uri = "file:///virtual/navigation_dependency.tn"
    main_uri = "file:///virtual/navigation_main.tn"
    dependency = "def answer(value : Int32) : Int32\n  value\nend\n"
    main = "require \"./navigation_dependency\"\nputs answer(7)\n"
    messages = EditorNavigationSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: dependency_uri, text: dependency, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: main_uri, text: main, version: 1}}},
      {jsonrpc: "2.0", id: 7, method: "textDocument/references", params: {textDocument: {uri: main_uri}, position: {line: 1, character: 7}, context: {includeDeclaration: true}}},
    ])

    references = EditorNavigationSpecSupport.response(messages, 7).as_a
    references.map { |location| location["uri"].as_s }.should eq([dependency_uri, main_uri])
  end

  it "adds declaration documentation to structured hover text" do
    uri = "file:///virtual/navigation_docs.tn"
    source = <<-TANGO
      # Adds one to the supplied value.
      def add_one(value : Int32) : Int32
        value + 1
      end

      puts add_one(2)
      TANGO
    messages = EditorNavigationSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 8, method: "textDocument/hover", params: {textDocument: {uri: uri}, position: {line: 5, character: 7}}},
    ])

    hover = EditorNavigationSpecSupport.response(messages, 8)
    hover["contents"]["kind"].as_s.should eq("markdown")
    hover["contents"]["value"].as_s.should eq(<<-MARKDOWN.chomp)
      ```tango
      def add_one(value : Int32) : Int32
      ```

      Adds one to the supplied value.
      MARKDOWN
  end

  it "advertises exactly the implemented request capabilities" do
    messages = EditorNavigationSpecSupport.run([
      {jsonrpc: "2.0", id: 9, method: "initialize", params: {} of String => String},
    ])
    capabilities = EditorNavigationSpecSupport.response(messages, 9)["capabilities"]

    capabilities["documentSymbolProvider"].as_bool.should be_true
    capabilities["workspaceSymbolProvider"].as_bool.should be_true
    capabilities["referencesProvider"].as_bool.should be_true
    capabilities["documentHighlightProvider"].as_bool.should be_true
  end
end
