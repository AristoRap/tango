require "../spec_helper"
require "../../src/tango/dump"

private PARITY_FIXTURES = File.join("spec", "fixtures", "source_graph_diagnostics")

private def parity_snapshots(kind : String)
  entry = File.join(PARITY_FIXTURES, kind, "main.tn")
  source = File.read(entry)
  {
    Tango.snapshot(source, filename: entry),
    Tango.pre_target_snapshot(source, filename: entry),
  }
end

describe "full and pre-target snapshot parity" do
  it "keeps development and release identical before a candidate clears its gate" do
    entry = File.join("examples", "string_split.tn")
    source = File.read(entry)
    development = Tango.snapshot(source, filename: entry)
    release = Tango.snapshot(source, filename: entry, profile: Tango::Compiler::CompilationProfile::Release)

    development.diagnostics.should eq(release.diagnostics)
    Tango::Dump::NIR.render(development).should eq(Tango::Dump::NIR.render(release))
    Tango::Dump::Facts.render(development).should eq(Tango::Dump::Facts.render(release))
    development.editor_index.occurrences.should eq(release.editor_index.occurrences)

    Tango::Dump::Plans.render(development).should eq(Tango::Dump::Plans.render(release))
    Tango::Dump::LIR.render(development).should eq(Tango::Dump::LIR.render(release))
    development.go_source.should eq(release.go_source)
  end

  it "shares recursive glob expansion through the LIR boundary" do
    entry = File.join("examples", "require_graph.tn")
    source = File.read(entry)
    full = Tango.snapshot(source, filename: entry)
    pre_target = Tango.pre_target_snapshot(source, filename: entry)

    full.source.files.map(&.path).should eq(pre_target.source.files.map(&.path))
    full.source.edges.should eq(pre_target.source.edges)
    full.diagnostics.should eq(pre_target.diagnostics)
    Tango::Dump::NIR.render(full).should eq(Tango::Dump::NIR.render(pre_target))
    Tango::Dump::Facts.render(full).should eq(Tango::Dump::Facts.render(pre_target))
    Tango::Dump::Plans.render(full).should eq(Tango::Dump::Plans.render(pre_target))
    Tango::Dump::LIR.render(full).should eq(Tango::Dump::LIR.render(pre_target))
    full.editor_index.occurrences.should eq(pre_target.editor_index.occurrences)
    full.go_source.should_not be_nil
    pre_target.go_source.should be_nil
  end

  it "shares the complete analyzed source graph before the target boundary" do
    full, pre_target = parity_snapshots("same_offset")

    full.source.files.map(&.path).should eq(pre_target.source.files.map(&.path))
    full.source.edges.should eq(pre_target.source.edges)
    full.diagnostics.should eq(pre_target.diagnostics)
    Tango::Dump::NIR.render(full).should eq(Tango::Dump::NIR.render(pre_target))
    Tango::Dump::Facts.render(full).should eq(Tango::Dump::Facts.render(pre_target))
    Tango::Dump::Plans.render(full).should eq(Tango::Dump::Plans.render(pre_target))
    Tango::Dump::LIR.render(full).should eq(Tango::Dump::LIR.render(pre_target))
    full.editor_index.declarations.should eq(pre_target.editor_index.declarations)
    full.editor_index.references.should eq(pre_target.editor_index.references)
    full.editor_index.occurrences.should eq(pre_target.editor_index.occurrences)
    full.target_ir.should_not be_nil
    full.go_source.should_not be_nil
    pre_target.target_ir.should be_nil
    pre_target.go_source.should be_nil
  end

  it "shares dependency diagnostics when compilation stops before NIR" do
    full, pre_target = parity_snapshots("type_error")

    full.source.files.map(&.path).should eq(pre_target.source.files.map(&.path))
    full.source.edges.should eq(pre_target.source.edges)
    full.diagnostics.should eq(pre_target.diagnostics)
    full.nir.should be_nil
    pre_target.nir.should be_nil
  end
end
