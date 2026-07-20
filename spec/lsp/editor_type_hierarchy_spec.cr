require "../spec_helper"
require "../../src/tango/lsp"

module EditorHierarchySpecSupport
  def self.frame(payload) : String
    body = payload.to_json
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def self.request(payload) : JSON::Any
    JSON.parse(payload.to_json)
  end

  def self.run(requests : Array(JSON::Any)) : Array(JSON::Any)
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

  def self.item_request(uri : String, item : Tango::Compiler::Editor::Index::HierarchyFacts::Item)
    {
      name:           item.name,
      kind:           item.kind.capability? ? 11 : (item.kind.struct? ? 23 : 5),
      uri:            uri,
      range:          {start: {line: 0, character: 0}, end: {line: 0, character: 1}},
      selectionRange: {start: {line: 0, character: 0}, end: {line: 0, character: 1}},
      data:           Tango::Lsp::AnalysisCodec::HierarchyKeyData.new(item.key),
    }
  end
end

describe "editor type hierarchy" do
  it "advertises and projects all three exact type-hierarchy request shapes" do
    path = "/virtual/hierarchy_capability.tn"
    uri = "file://#{path}"
    source = <<-TN
      module Counted
        abstract def count : Int32
      end

      struct Bag
        include Counted
        def count : Int32
          1
        end
      end

      def consume(value : Counted) : Int32
        value.count
      end

      puts consume(Bag.new)
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: path)
    items = snapshot.editor_index.hierarchy.items
    counted = items.find!(&.name.==("Counted"))
    bag = items.find!(&.name.==("Bag"))

    messages = EditorHierarchySpecSupport.run([
      EditorHierarchySpecSupport.request({jsonrpc: "2.0", id: 1, method: "initialize", params: {} of String => String}),
      EditorHierarchySpecSupport.request({jsonrpc: "2.0", method: "textDocument/didOpen", params: {textDocument: {uri: uri, text: source, version: 1}}}),
      EditorHierarchySpecSupport.request({jsonrpc: "2.0", id: 2, method: "textDocument/prepareTypeHierarchy", params: {textDocument: {uri: uri}, position: {line: 0, character: 9}}}),
      EditorHierarchySpecSupport.request({jsonrpc: "2.0", id: 3, method: "typeHierarchy/subtypes", params: {item: EditorHierarchySpecSupport.item_request(uri, counted)}}),
      EditorHierarchySpecSupport.request({jsonrpc: "2.0", id: 4, method: "typeHierarchy/supertypes", params: {item: EditorHierarchySpecSupport.item_request(uri, bag)}}),
      EditorHierarchySpecSupport.request({jsonrpc: "2.0", id: 5, method: "typeHierarchy/supertypes", params: {item: EditorHierarchySpecSupport.item_request(uri, counted)}}),
    ])

    EditorHierarchySpecSupport.response(messages, 1)["capabilities"]["typeHierarchyProvider"].as_bool.should be_true

    prepared = EditorHierarchySpecSupport.response(messages, 2).as_a
    prepared.size.should eq(1)
    prepared.first["name"].as_s.should eq("Counted")
    prepared.first["kind"].as_i.should eq(11)
    prepared.first["detail"].as_s.should eq("capability (reached implementations only; partial)")
    prepared.first["range"].should eq(JSON.parse(%({"start":{"line":0,"character":0},"end":{"line":2,"character":3}})))
    prepared.first["selectionRange"].should eq(JSON.parse(%({"start":{"line":0,"character":7},"end":{"line":0,"character":14}})))
    prepared.first["data"]["type"]["name"].as_s.should eq("Counted")
    prepared.first["data"]["declaration"]["start_offset"].as_i.should eq(7)

    implementations = EditorHierarchySpecSupport.response(messages, 3).as_a
    implementations.map { |item| item["name"].as_s }.should eq(["Bag"])
    implementations.first["kind"].as_i.should eq(23)
    implementations.first["detail"].as_s.should eq("reached capability implementation (partial)")

    capabilities = EditorHierarchySpecSupport.response(messages, 4).as_a
    capabilities.map { |item| item["name"].as_s }.should eq(["Counted"])
    capabilities.first["detail"].as_s.should eq("proven capability conformance (reached; partial)")
    EditorHierarchySpecSupport.response(messages, 5).as_a.should be_empty
  end

  it "returns exact direct source superclass edges in deterministic order" do
    path = "/virtual/hierarchy_classes.tn"
    source = <<-TN
      class Base
      end

      class Zeta < Base
      end

      class Alpha < Base
      end

      puts 1
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: path)
    snapshot.diagnostics.should be_empty
    base = Tango::Compiler::Editor::TypeHierarchy.prepare(snapshot, path, 1, 7).first
    alpha = Tango::Compiler::Editor::TypeHierarchy.prepare(snapshot, path, 7, 7).first

    subtypes = expect_present(Tango::Compiler::Editor::TypeHierarchy.subtypes(snapshot, base.key))
    subtypes.map(&.item.name).should eq(["Alpha", "Zeta"])
    subtypes.each do |related|
      related.kind.superclass?.should be_true
      related.completeness.exact?.should be_true
    end

    supertypes = expect_present(Tango::Compiler::Editor::TypeHierarchy.supertypes(snapshot, alpha.key))
    supertypes.map(&.item.name).should eq(["Base"])
    supertypes.first.completeness.exact?.should be_true
  end

  it "uses resolved superclass identity and omits parents without Tango ranges" do
    path = "/virtual/hierarchy_resolved_classes.tn"
    source = <<-TN
      class Base
      end

      alias Parent = Base

      class Child < Parent
      end

      class BuiltinChild < Exception
      end

      puts 1
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: path)
    child = snapshot.editor_index.hierarchy.items.find!(&.name.==("Child"))
    builtin = snapshot.editor_index.hierarchy.items.find!(&.name.==("BuiltinChild"))

    resolved = expect_present(Tango::Compiler::Editor::TypeHierarchy.supertypes(snapshot, child.key))
    resolved.map(&.item.name).should eq(["Base"])
    expect_present(Tango::Compiler::Editor::TypeHierarchy.supertypes(snapshot, builtin.key)).should be_empty
    snapshot.editor_index.hierarchy.items.map(&.name).should_not contain("Exception")
  end

  it "publishes only Crystal-proven capability witnesses and names them partial" do
    path = "/virtual/hierarchy_witnesses.tn"
    reached = <<-TN
      module Counted
        abstract def count : Int32
      end

      struct Crate
        include Counted
        def count : Int32
          2
        end
      end

      struct Bag
        include Counted
        def count : Int32
          1
        end
      end

      def consume(value : Counted) : Int32
        value.count
      end

      puts consume(Crate.new)
      puts consume(Bag.new)
      TN
    snapshot = Tango.pre_target_snapshot(reached, filename: path)
    counted = snapshot.editor_index.hierarchy.items.find!(&.name.==("Counted"))
    implementations = expect_present(Tango::Compiler::Editor::TypeHierarchy.subtypes(snapshot, counted.key))
    implementations.map(&.item.name).should eq(["Bag", "Crate"])
    implementations.each do |related|
      related.kind.capability?.should be_true
      related.completeness.reached_partial?.should be_true
    end

    unreached = <<-TN
      module Counted
        abstract def count : Int32
      end

      struct Crate
        include Counted
        def count : Int32
          2
        end
      end

      struct Bag
        include Counted
        def count : Int32
          1
        end
      end

      puts 1
      TN
    unreached_snapshot = Tango.pre_target_snapshot(unreached, filename: path)
    unreached_counted = unreached_snapshot.editor_index.hierarchy.items.find!(&.name.==("Counted"))
    expect_present(Tango::Compiler::Editor::TypeHierarchy.subtypes(unreached_snapshot, unreached_counted.key)).should be_empty
  end

  it "survives the analysis codec without compiler phase objects" do
    path = "/virtual/hierarchy_codec.tn"
    source = "class Base\nend\nclass Child < Base\nend\nputs 1\n"
    snapshot = Tango.pre_target_snapshot(source, filename: path)
    projected = Tango::Lsp::AnalysisCodec.load(Tango::Lsp::AnalysisCodec.dump(snapshot))

    projected.nir.should be_nil
    projected.facts.should be_nil
    projected.editor_index.hierarchy.items.should eq(snapshot.editor_index.hierarchy.items)
    projected.editor_index.hierarchy.relations.should eq(snapshot.editor_index.hierarchy.relations)
    child = projected.editor_index.hierarchy.items.find!(&.name.==("Child"))
    expect_present(Tango::Compiler::Editor::TypeHierarchy.supertypes(projected, child.key)).map(&.item.name).should eq(["Base"])
  end

  it "pins the source completeness boundary on both driving documents" do
    indexable_path = File.expand_path("../../examples/indexable.tn", __DIR__)
    indexable = Tango.pre_target_snapshot(File.read(indexable_path), filename: indexable_path)
    buffer = Tango::Compiler::Editor::TypeHierarchy.prepare(indexable, indexable_path, 1, 8).first
    buffer.name.should eq("Buffer")
    expect_present(Tango::Compiler::Editor::TypeHierarchy.supertypes(indexable, buffer.key)).should be_empty
    expect_present(Tango::Compiler::Editor::TypeHierarchy.subtypes(indexable, buffer.key)).should be_empty

    capability_path = File.expand_path("../../examples/capability_dispatch.tn", __DIR__)
    capability = Tango.pre_target_snapshot(File.read(capability_path), filename: capability_path)
    Tango::Compiler::Editor::TypeHierarchy.prepare(capability, capability_path, 1, 20).should be_empty
    capability.editor_index.hierarchy.items.should be_empty
  end
end
