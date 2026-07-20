require "spec"
require "../../src/tango/core"

describe "the standalone Tango compiler core entrypoint" do
  it "runs a bundled neutral frontend failure without loading a host adapter" do
    source = Tango::Source::CompilationUnit.single(
      Tango::Source::File.new("neutral_failure.tn", "")
    )
    diagnostic = Tango::Diagnostic.new(
      Tango::Diagnostic::Origin::Frontend,
      Tango::Diagnostic::Severity::Error,
      Tango::Diagnostics::FRONT_SYNTAX,
      "neutral failure"
    )
    frontend = Tango::Frontend::Result.new(source, diagnostics: [diagnostic])
    bundle = Tango::Frontend::Bundle::Document.from(
      frontend,
      frontend_version: "fixture-frontend",
      prelude_version: "fixture-prelude"
    )

    snapshot = Tango::Compiler::CoreDriver.run(bundle.to_frontend_result)

    snapshot.ok?.should be_false
    snapshot.diagnostics.should eq([diagnostic])
    snapshot.nir.should be_nil
  end
end
