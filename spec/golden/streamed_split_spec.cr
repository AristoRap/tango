require "../spec_helper"
require "../../src/tango/dump"

private alias StreamNIR = Tango::IR::NIR

private def streamed_split_snapshots(source : String, filename : String)
  {
    Tango.snapshot(source, filename: filename),
    Tango.snapshot(source, filename: filename, profile: Tango::Compiler::CompilationProfile::Release),
  }
end

private def run_streamed_split(snapshot : Tango::Compiler::Snapshot, filename : String) : String
  output = IO::Memory.new
  error = IO::Memory.new
  result = Tango::Toolchain::Go.run_source(expect_present(snapshot.go_source), filename, output, error)
  result.status.should eq(0)
  result.diagnostics.should be_empty
  error.to_s.should be_empty
  output.to_s
end

private def find_streamed_split(node : StreamNIR::Stmt) : StreamNIR::StringSplit?
  if split = node.as?(StreamNIR::StringSplit)
    return split if split.separator
  end
  StreamNIR::Walk.children(node).each do |child|
    find_streamed_split(child).try { |split| return split }
  end
  nil
end

private def find_streamed_split(program : StreamNIR::Program) : StreamNIR::StringSplit?
  program.body.each do |node|
    find_streamed_split(node).try { |split| return split }
  end
  nil
end

describe "release exact-split traversal" do
  source = <<-TANGO
    "a;;b;".split(";").each do |part|
      puts "<\#{part}>"
    end
    TANGO
  development, release = streamed_split_snapshots(source, "streamed_split.tn")
  split = expect_present(find_streamed_split(expect_present(release.nir)))

  it "keeps frontend meaning and output profile-independent" do
    development.diagnostics.should eq(release.diagnostics)
    Tango::Dump::NIR.render(development).should eq(Tango::Dump::NIR.render(release))
    Tango::Dump::Facts.render(development).should eq(Tango::Dump::Facts.render(release))
    development.editor_index.occurrences.should eq(release.editor_index.occurrences)

    expected = "<a>\n<>\n<b>\n<>\n"
    run_streamed_split(development, "streamed_split_development.tn").should eq(expected)
    run_streamed_split(release, "streamed_split_release.tn").should eq(expected)
  end

  it "selects and commits independent streaming source/each terminal axes only in Release" do
    development_plans = expect_present(development.plans)
    release_plans = expect_present(release.plans)
    development_plans.collection_productions[split.id].should be_a(Tango::Planning::Plans::MaterializedCollection)
    release_plans.collection_productions[split.id].should be_a(Tango::Planning::Plans::StreamedCollection)

    plans = Tango::Dump::Plans.render(release)
    plans.should contain("collection_production StreamedCollection Array(String)")
    plans.should contain("semantic_collection FusedCollectionTraversal Nil")

    lir = Tango::Dump::LIR.render(release)
    lir.should contain("FusedCollectionTraversal Nil Source=StringSegments")
    lir.should contain("Terminal=CollectionEachTerminal")
    release.go_source.to_s.should contain("func tangoStringSplitEach")
    release.go_source.to_s.should_not contain("func tangoStringSplitOn")
  end

  it "retains materialization for aliases, empty separators, and whitespace splitting" do
    cases = {
      "aliased" => <<-TANGO,
        parts = "a;b".split(";")
        parts.each { |part| puts part }
        TANGO
      "empty separator" => <<-TANGO,
        "ab".split("").each { |part| puts part }
        TANGO
      "whitespace" => <<-TANGO,
        "a b".split.each { |part| puts part }
        TANGO
    }

    cases.each do |name, candidate|
      snapshot = Tango.snapshot(candidate, filename: "#{name.gsub(' ', '_')}.tn", profile: Tango::Compiler::CompilationProfile::Release)
      productions = expect_present(snapshot.plans).collection_productions.values
      productions.should_not be_empty, name
      productions.all?(&.is_a?(Tango::Planning::Plans::MaterializedCollection)).should be_true, name
    end
  end
end
