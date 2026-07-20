require "../../spec_helper"
require "./fixture"

describe Tango::Frontend::Bundle::Document do
  it "rejects unknown schema versions before they enter the core" do
    result = BundleSpec.result
    provenance = Tango::Frontend::Bundle::Provenance.new(
      0,
      result.source.requires,
      result.source.edges
    )

    [0, Tango::Frontend::Bundle::Document::CURRENT_SCHEMA_VERSION + 1].each do |unknown_version|
      error = expect_raises(Tango::Frontend::Bundle::UnsupportedVersionError) do
        Tango::Frontend::Bundle::Document.new(
          schema_version: unknown_version,
          frontend_version: "fixture-frontend",
          prelude_version: "fixture-prelude",
          source_table: result.source.files.map { |file| Tango::Frontend::Bundle::Source.from(file) },
          normalized_nir: result.program,
          syntax_surface: result.syntax_surface,
          frontend_diagnostics: result.diagnostics,
          source_provenance: provenance
        )
      end

      error.actual.should eq(unknown_version)
      error.supported.should eq(1)
      error.message.should eq(
        "unsupported semantic bundle schema version #{unknown_version}; supported version is 1"
      )
    end
  end

  it "round-trips the in-process document without losing IDs, spans, or provenance" do
    original = BundleSpec.result
    document = BundleSpec.document
    restored = document.to_frontend_result
    canonical = Tango::Frontend::Bundle::Document.from(
      restored,
      frontend_version: document.frontend_version,
      prelude_version: document.prelude_version
    )

    canonical.schema_version.should eq(document.schema_version)
    canonical.frontend_version.should eq(document.frontend_version)
    canonical.prelude_version.should eq(document.prelude_version)
    canonical.source_table.should eq(document.source_table)
    canonical.source_provenance.should eq(document.source_provenance)
    canonical.frontend_diagnostics.should eq(document.frontend_diagnostics)
    canonical.syntax_surface.declarations.should eq(document.syntax_surface.declarations)
    canonical.syntax_surface.scopes.should eq(document.syntax_surface.scopes)

    restored.source.entrypoint.identity.should eq("source-main")
    restored.source.entrypoint.stable_path?.should be_false
    restored.source.files.map(&.identity).should eq(["source-main", "source-answer"])
    restored.source.requires.should eq(original.source.requires)
    restored.source.edges.should eq(original.source.edges)

    program = expect_present(restored.program)
    literal = program.body.first.as(Tango::IR::NIR::IntLiteral)
    literal.id.should eq(Tango::NodeId.new("semantic-42"))
    literal.span.should eq(Tango::Source::Range.new("/workspace/answer.tn", 13, 15, 2, 3))
  end
end
