require "../../spec_helper"
require "./fixture"

describe Tango::Frontend::Bundle::Codec do
  it "emits deterministic canonical schema-v1 JSON and preserves every document family" do
    document = BundleSpec.document
    encoded = Tango::Frontend::Bundle::Codec.dump(document)
    restored = Tango::Frontend::Bundle::Codec.load(encoded)

    Tango::Frontend::Bundle::Codec.dump(document).should eq(encoded)
    Tango::Frontend::Bundle::Codec.dump(restored).should eq(encoded)
    restored.source_table.should eq(document.source_table)
    restored.source_provenance.should eq(document.source_provenance)
    restored.syntax_surface.declarations.should eq(document.syntax_surface.declarations)
    restored.syntax_surface.scopes.should eq(document.syntax_surface.scopes)
    restored.frontend_diagnostics.should eq(document.frontend_diagnostics)

    program = expect_present(restored.normalized_nir)
    program.body.first.as(Tango::IR::NIR::IntLiteral).id.should eq(Tango::NodeId.new("semantic-42"))
    program.type_annotations.keys.map(&.to_s).should eq(["Int32"])
    target_annotation = program.type_annotations.values.first.first
    target_annotation.path.should eq(["Go", "Type"])
    target_annotation.string_args.should eq(["int32"])
    target_annotation.symbol_args.should eq(["value"])
  end

  it "rejects unsupported versions before attempting to decode their body" do
    error = expect_raises(Tango::Frontend::Bundle::UnsupportedVersionError) do
      Tango::Frontend::Bundle::Codec.load(%({"schema_version":2,"future_shape":true}))
    end

    error.actual.should eq(2)
    error.supported.should eq(1)
  end

  it "rejects unknown fields and node kinds with a structured location" do
    encoded = Tango::Frontend::Bundle::Codec.dump(BundleSpec.document)

    field_error = expect_raises(Tango::Frontend::Bundle::CodecError) do
      Tango::Frontend::Bundle::Codec.load(encoded.sub(%({"schema_version":1), %({"schema_version":1,"surprise":true)))
    end
    field_error.location.should eq("$")
    field_error.message.to_s.should contain(%(unknown field "surprise"))

    node_field_error = expect_raises(Tango::Frontend::Bundle::CodecError) do
      Tango::Frontend::Bundle::Codec.load(encoded.sub(%("kind":"int_literal"), %("kind":"int_literal","surprise":true)))
    end
    node_field_error.location.should eq("$.normalized_nir.body[0]")
    node_field_error.message.to_s.should contain(%(unknown field "surprise"))

    metadata_error = expect_raises(Tango::Frontend::Bundle::CodecError) do
      Tango::Frontend::Bundle::Codec.load(encoded.sub(%(,"method_site":null), ""))
    end
    metadata_error.location.should eq("$.normalized_nir.body[0]")
    metadata_error.message.to_s.should contain("missing expression metadata")

    kind_error = expect_raises(Tango::Frontend::Bundle::CodecError) do
      Tango::Frontend::Bundle::Codec.load(encoded.sub(%("kind":"int_literal"), %("kind":"future_node")))
    end
    kind_error.location.should eq("$.normalized_nir.body[0].kind")
    kind_error.message.to_s.should contain(%(unknown NIR node kind "future_node"))

    index_error = expect_raises(Tango::Frontend::Bundle::CodecError) do
      Tango::Frontend::Bundle::Codec.load(encoded.sub(%("entrypoint_index":0), %("entrypoint_index":99)))
    end
    index_error.location.should eq("$.source_provenance.entrypoint_index")
  end

  it "preserves canonical bundles, diagnostics, and Go through every checked-in example" do
    root = File.expand_path("../../..", __DIR__)
    Dir.glob(File.join(root, "examples", "*.tn")).sort.each do |path|
      name = File.basename(path)
      file = Tango::Source::File.canonical(path, File.read(path))
      frontend = Tango::Compiler::Driver.frontend(file, Tango::Frontend::SourceGraph::DISK_RESOLVER)

      document = Tango::Frontend::Bundle::Document.from(
        frontend,
        frontend_version: "crystal-1.20.2",
        prelude_version: "fixture-prelude"
      )
      encoded = Tango::Frontend::Bundle::Codec.dump(document)
      restored = Tango::Frontend::Bundle::Codec.load(encoded)
      Tango::Frontend::Bundle::Codec.dump(restored).should eq(encoded), name
      decoded = restored.to_frontend_result

      original_snapshot = Tango::Compiler::CoreDriver.run(frontend)
      decoded_snapshot = Tango::Compiler::CoreDriver.run(decoded)
      decoded_snapshot.diagnostics.should eq(original_snapshot.diagnostics), name
      decoded_snapshot.go_source.should eq(original_snapshot.go_source), name
    end
  end
end
