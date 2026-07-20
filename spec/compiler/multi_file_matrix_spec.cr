require "../spec_helper"
require "../../src/tango/dump"

private SOURCE_GRAPH_MATRIX_FIXTURES = File.join("spec", "fixtures", "source_graph_matrix")
private SOURCE_GRAPH_EXAMPLE         = File.join("examples", "require_graph.tn")

private def source_graph_matrix_snapshot(kind : String) : Tango::Compiler::Snapshot
  entry = File.join(SOURCE_GRAPH_MATRIX_FIXTURES, kind, "main.tn")
  Tango.snapshot(File.read(entry), filename: entry)
end

private def matrix_names(snapshot : Tango::Compiler::Snapshot) : Array(String)
  snapshot.source.files.map { |file| File.basename(file.path) }
end

describe "adversarial source graph" do
  it "resolves nested explicit and implied extensions relative to each requiring file" do
    snapshot = source_graph_matrix_snapshot("nested_paths")

    snapshot.diagnostics.should be_empty
    matrix_names(snapshot).should eq(%w(shared.tn middle.tn main.tn))
    snapshot.source.edges.map(&.request).should eq(["./nested/middle.tn", "../shared"])
  end

  it "keeps every direct-duplicate edge while loading the canonical file once" do
    snapshot = source_graph_matrix_snapshot("direct_duplicate")

    snapshot.diagnostics.should be_empty
    matrix_names(snapshot).should eq(%w(shared.tn main.tn))
    snapshot.source.edges.map(&.request).should eq(["./shared", "./shared.tn"])
    snapshot.source.edges.map(&.to).uniq.size.should eq(1)
  end

  it "loads a diamond dependency-first and retains both edges to the shared file" do
    snapshot = source_graph_matrix_snapshot("diamond")

    snapshot.diagnostics.should be_empty
    matrix_names(snapshot).should eq(%w(shared.tn left.tn right.tn main.tn))
    snapshot.source.edges.map(&.request).should eq(["./left", "./shared", "./right", "./shared.tn"])
    snapshot.source.edges.count { |edge| File.basename(edge.to) == "shared.tn" }.should eq(2)
  end

  it "terminates cycles without dropping the request-site back edge" do
    snapshot = source_graph_matrix_snapshot("cycle")

    snapshot.diagnostics.should be_empty
    matrix_names(snapshot).should eq(%w(second.tn first.tn main.tn))
    snapshot.source.edges.map(&.request).should eq(["./first", "./second", "./first.tn"])
    snapshot.source.edges.last.to.should eq(snapshot.source.files.find! { |file| File.basename(file.path) == "first.tn" }.path)
  end

  it "expands a non-recursive glob in stable lexical order without descending" do
    snapshot = source_graph_matrix_snapshot("glob")

    snapshot.diagnostics.should be_empty
    matrix_names(snapshot).should eq(%w(alpha.tn zeta.tn main.tn))
    snapshot.source.edges.map { |edge| File.basename(edge.to) }.should eq(%w(alpha.tn zeta.tn))
    snapshot.source.edges.map(&.request).should eq(["./support/*", "./support/*"])
  end

  it "expands recursive globs through the full semantic and editor pipeline" do
    snapshot = Tango.snapshot(File.read(SOURCE_GRAPH_EXAMPLE), filename: SOURCE_GRAPH_EXAMPLE)
    files = snapshot.source.files

    snapshot.diagnostics.should be_empty
    files.map { |file| File.basename(file.path) }.should eq(%w(00_math.tn 10_point.tn 20_combined.tn require_graph.tn))
    snapshot.source.edges.size.should eq(4)
    snapshot.source.edges.first(3).map(&.request).should eq(Array.new(3, "./support/require_graph/**"))
    snapshot.editor_index.declarations.any? { |decl| decl.name == "Point" && decl.range.path.ends_with?("10_point.tn") }.should be_true
    snapshot.editor_index.declarations.any? { |decl| decl.name == "x" && decl.range.path.ends_with?("10_point.tn") }.should be_true
    snapshot.editor_index.declarations.any? { |decl| decl.name == "combined" && decl.range.path.ends_with?("20_combined.tn") }.should be_true
    snapshot.editor_index.references.any? { |ref| ref.range.path.ends_with?("20_combined.tn") }.should be_true
    snapshot.go_source.to_s.should contain("func combined_Point")
  end

  it "diagnoses empty globs, forbidden requests, and stdin without a stable base" do
    empty = source_graph_matrix_snapshot("empty_glob").diagnostics.first
    bare = Tango.snapshot("require \"json\"\n", filename: "bare.tn").diagnostics.first
    absolute = Tango.snapshot("require \"/tmp/private.tn\"\n", filename: "absolute.tn").diagnostics.first
    stdin = Tango.snapshot(
      "require \"./local\"\n",
      filename: "stdin.tn",
      stable_path: false
    ).diagnostics.first

    empty.message.should contain("matched no `.tn` files")
    bare.message.should contain("must use a relative path")
    bare.message.should contain("or a bundled package")
    absolute.message.should contain("must use a relative path")
    stdin.message.should contain("stdin need a named entry file")
    [empty, bare, absolute, stdin].each do |diagnostic|
      diagnostic.origin.frontend?.should be_true
      diagnostic.range.should_not be_nil
      diagnostic.size.should be > 1
    end
  end

  it "shares one recursive graph header across every phase dump" do
    snapshot = Tango.snapshot(File.read(SOURCE_GRAPH_EXAMPLE), filename: SOURCE_GRAPH_EXAMPLE)
    header = Tango::Dump::SourceGraphHeader.render(snapshot.source)
    dumps = [
      Tango::Dump::NIR.render(snapshot),
      Tango::Dump::Facts.render(snapshot),
      Tango::Dump::Plans.render(snapshot),
      Tango::Dump::LIR.render(snapshot),
    ]

    dumps.each do |dump|
      dump.should start_with(header)
      dump.should_not match(/\bRequire\b/)
    end
    header.scan("request=\"./support/require_graph/**\"").size.should eq(3)
    header.should contain("request=\"../00_math\"")
  end
end
