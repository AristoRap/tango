require "../spec_helper"
require "../../src/tango/lsp"

module EditorCompletionSpecSupport
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
end

describe "editor completion and signature help" do
  it "completes only valid bundled require paths" do
    uri = "file:///virtual/completion_require.tn"
    source = %(require "tango/fs")
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 1, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 0, character: 15}}},
    ])

    result = EditorCompletionSpecSupport.response(messages, 1)
    result["isIncomplete"].as_bool.should be_false
    items = result["items"].as_a
    items.map { |item| item["label"].as_s }.should eq(["tango/fs"])
    edit = items.first["textEdit"]
    edit["newText"].as_s.should eq("tango/fs")
    edit["range"]["start"]["character"].as_i.should eq(9)
    edit["range"]["end"]["character"].as_i.should eq(17)
  end

  it "completes exact semantic receiver members and excludes private members" do
    uri = "file:///virtual/completion_member.tn"
    valid = <<-TANGO
      class Settings
        def locale(code : String) : String
          code
        end

        private def secret(code : String) : String
          code
        end
      end

      settings = Settings.new
      puts "😀"; settings.locale("en")
      TANGO
    broken = valid.sub(%(puts "😀"; settings.locale("en")), %(puts "😀"; settings.))
    stale = broken.sub("settings.", "unknown_receiver.")
    cursor = %(puts "😀"; settings.).size + 1 # UTF-16 counts 😀 as two units.
    stale_cursor = %(puts "😀"; unknown_receiver.).size + 1
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", id: 110, method: "textDocument/semanticTokens/full", params: {textDocument: {uri: uri}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: broken}]}},
      {jsonrpc: "2.0", id: 2, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 11, character: cursor}}},
    ])
    stale_messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 3}, contentChanges: [{text: stale}]}},
      {jsonrpc: "2.0", id: 3, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 11, character: stale_cursor}}},
    ])

    exact = EditorCompletionSpecSupport.response(messages, 2)
    exact["isIncomplete"].as_bool.should be_false
    labels = exact["items"].as_a.map { |item| item["label"].as_s }
    labels.should contain("locale")
    labels.should_not contain("secret")
    locale = exact["items"].as_a.find! { |item| item["label"].as_s == "locale" }
    locale["textEdit"]["range"]["start"]["character"].as_i.should eq(cursor)

    rejected = EditorCompletionSpecSupport.response(stale_messages, 3)
    rejected["isIncomplete"].as_bool.should be_true
    rejected["items"].as_a.should be_empty
  end

  it "limits bare completion to the current lexical scope" do
    uri = "file:///virtual/completion_bare.tn"
    source = <<-TANGO
      def left(other : Int32) : Int32
        hidden = other
        hidden
      end

      def right(input : Int32) : Int32
        local_count = input
        loc
      end
      TANGO
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 4, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 7, character: 5}}},
    ])

    labels = EditorCompletionSpecSupport.response(messages, 4)["items"].as_a.map { |item| item["label"].as_s }
    labels.should eq(["local_count"])
    labels.should_not contain("hidden")
    labels.should_not contain("other")
  end

  it "does not offer initialize on the instance receiver from examples/class.tn" do
    path = File.expand_path("../../examples/class.tn", __DIR__)
    uri = "file://#{path}"
    valid = File.read(path)
    broken = valid.sub("puts p.x", "puts p.")
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", id: 111, method: "textDocument/semanticTokens/full", params: {textDocument: {uri: uri}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: broken}]}},
      {jsonrpc: "2.0", id: 11, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 12, character: 7}}},
    ])

    labels = EditorCompletionSpecSupport.response(messages, 11)["items"].as_a.map { |item| item["label"].as_s }
    labels.should contain("x")
    labels.should_not contain("initialize")
  end

  it "does not merge members from unrelated same-named types" do
    uri = "file:///virtual/completion_same_named_types.tn"
    valid = <<-TANGO
      module Alpha
        class Settings
          def alpha : Int32
            1
          end
        end
      end

      module Beta
        class Settings
          def beta : Int32
            2
          end
        end
      end

      alpha = Alpha::Settings.new
      beta = Beta::Settings.new
      puts alpha.alpha + beta.beta
      TANGO
    broken = valid.sub("puts alpha.alpha + beta.beta", "puts alpha.")
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", id: 112, method: "textDocument/semanticTokens/full", params: {textDocument: {uri: uri}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: broken}]}},
      {jsonrpc: "2.0", id: 10, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 18, character: 11}}},
    ])

    labels = EditorCompletionSpecSupport.response(messages, 10)["items"].as_a.map { |item| item["label"].as_s }
    labels.should contain("alpha")
    labels.should_not contain("beta")
  end

  it "shows a required class method signature from compatible last-good facts" do
    uri = "file:///virtual/completion_file_signature.tn"
    valid = %(require "tango/fs"\n\nputs File.read("x")\n)
    broken = "require \"tango/fs\"\n\nputs File.read(\n"
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", id: 12, method: "textDocument/signatureHelp", params: {textDocument: {uri: uri}, position: {line: 2, character: 15}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: broken}]}},
      {jsonrpc: "2.0", id: 5, method: "textDocument/signatureHelp", params: {textDocument: {uri: uri}, position: {line: 2, character: 15}}},
    ])

    current = EditorCompletionSpecSupport.response(messages, 12)
    current["signatures"].as_a.first["label"].as_s.should eq("File.read(path : String) : String")

    result = EditorCompletionSpecSupport.response(messages, 5)
    result["activeSignature"].as_i.should eq(0)
    result["activeParameter"].as_i.should eq(0)
    signature = result["signatures"].as_a.first
    signature["label"].as_s.should eq("File.read(path : String) : String")
    signature["parameters"].as_a.first["label"].as_s.should eq("path : String")
  end

  it "completes and shows signatures while File.read is typed from scratch" do
    uri = "file:///virtual/completion_file_typing.tn"
    prefix = "require \"tango/fs\"\n\n"
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: prefix + "File\n", version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: prefix + "File.\n"}]}},
      {jsonrpc: "2.0", id: 13, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 2, character: 5}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 3}, contentChanges: [{text: prefix + "File.read()\n"}]}},
      {jsonrpc: "2.0", id: 14, method: "textDocument/signatureHelp", params: {textDocument: {uri: uri}, position: {line: 2, character: 10}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 4}, contentChanges: [{text: prefix + "File.read(\"\")\n"}]}},
      {jsonrpc: "2.0", id: 15, method: "textDocument/signatureHelp", params: {textDocument: {uri: uri}, position: {line: 2, character: 11}}},
    ])

    completion = EditorCompletionSpecSupport.response(messages, 13)
    completion["isIncomplete"].as_bool.should be_false
    completion["items"].as_a.map { |item| item["label"].as_s }.should contain("read")
    EditorCompletionSpecSupport.response(messages, 14)["signatures"].as_a.first["label"].as_s.should eq("File.read(path : String) : String")
    EditorCompletionSpecSupport.response(messages, 15)["signatures"].as_a.first["label"].as_s.should eq("File.read(path : String) : String")
  end

  it "keeps overloaded signature identity and the active parameter" do
    uri = "file:///virtual/completion_overloads.tn"
    valid = <<-TANGO
      # Integer choice.
      def choose(value : Int32, fallback : Int32) : Int32
        value
      end

      # String choice.
      def choose(value : String, fallback : String) : String
        value
      end

      puts choose("x", "y")
      TANGO
    broken = valid.sub(%(puts choose("x", "y")), %(puts choose("x", )))
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: valid, version: 1}}},
      {jsonrpc: "2.0", method: "textDocument/didChange", params: {textDocument: {uri: uri, version: 2}, contentChanges: [{text: broken}]}},
      {jsonrpc: "2.0", id: 6, method: "textDocument/signatureHelp", params: {textDocument: {uri: uri}, position: {line: 10, character: 17}}},
    ])

    result = EditorCompletionSpecSupport.response(messages, 6)
    result["activeParameter"].as_i.should eq(1)
    signatures = result["signatures"].as_a
    signatures.map { |signature| signature["label"].as_s }.sort.should eq([
      "choose(value : Int32, fallback : Int32) : Int32",
      "choose(value : String, fallback : String) : String",
    ])
    active = signatures[result["activeSignature"].as_i]
    active["label"].as_s.should contain("String")
    active["documentation"]["value"].as_s.should eq("String choice.")
  end

  it "does not complete ordinary strings or comments" do
    uri = "file:///virtual/completion_lexical_negative.tn"
    source = %(puts "settings."\n# settings.\n)
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}},
      {jsonrpc: "2.0", id: 7, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 0, character: 14}}},
      {jsonrpc: "2.0", id: 8, method: "textDocument/completion", params: {textDocument: {uri: uri}, position: {line: 1, character: 11}}},
    ])

    EditorCompletionSpecSupport.response(messages, 7)["items"].as_a.should be_empty
    EditorCompletionSpecSupport.response(messages, 8)["items"].as_a.should be_empty
  end

  it "advertises explicit completion and signature-help triggers" do
    messages = EditorCompletionSpecSupport.run([
      {jsonrpc: "2.0", id: 9, method: "initialize", params: {} of String => String},
    ])
    capabilities = EditorCompletionSpecSupport.response(messages, 9)["capabilities"]

    capabilities["completionProvider"]["triggerCharacters"].as_a.map(&.as_s).should eq([".", "\"", "/"])
    capabilities["signatureHelpProvider"]["triggerCharacters"].as_a.map(&.as_s).should eq(["(", ","])
  end
end
