require "./spec_helper"

describe Tango::Source::LineIndex do
  it "maps byte offsets to one-based byte line and column pairs" do
    index = Tango::Source::LineIndex.new("a\nbc")

    index.byte_line_col(0).should eq({1, 1})
    index.byte_line_col(2).should eq({2, 1})
    index.byte_offset_at(2, 2).should eq(3)
  end
end

describe Tango::Source::File do
  it "centralizes canonical identity while retaining the displayed path" do
    path = File.join("spec", "source_spec.cr")
    file = Tango::Source::File.canonical(path, "fixture")

    file.path.should eq(path)
    file.identity.should eq(File.realpath(path))
    file.stable_path?.should be_true
  end

  it "keeps source line and column on ranges built from parser locations" do
    file = Tango::Source::File.new("probe.tn", "a\nbc")
    range = file.range_at(2, 2)

    range.path.should eq("probe.tn")
    range.start_offset.should eq(3)
    range.line.should eq(2)
    range.column.should eq(2)
  end

  it "recovers complete quoted and numeric literals from a point span" do
    file = Tango::Source::File.new("probe.tn", "word = \"7\"\ncount = 42_i8")

    quoted = file.token_range_at(1, 8)
    numeric = file.token_range_at(2, 9)

    [quoted, numeric].map { |range| file.code.byte_slice(range.start_offset, range.length) }.should eq(["\"7\"", "42_i8"])
  end

  it "keeps an identifier point span intact" do
    file = Tango::Source::File.new("probe.tn", "Settings")
    range = file.token_range_at(1, 1)

    range.length.should eq(1)
    file.code.byte_slice(range.start_offset, range.length).should eq("S")
  end

  it "finds a quoted local require path without resolving it" do
    file = Tango::Source::File.new("probe.tn", "require \"./missing\"\nputs 1")
    range = file.require_path_range_at(1, 1)

    range.should_not be_nil
    found = expect_present(range)
    found.line.should eq(1)
    found.column.should eq(9)
    file.code.byte_slice(found.start_offset, found.length).should eq("\"./missing\"")
    file.require_path_range_at(2, 1).should be_nil
  end
end

describe Tango::Frontend::SourceGraph::Loader do
  it "resolves the explicit tango/fs package from the Tango-owned bundled root" do
    entry = Tango::Source::File.new("/virtual/main.tn", "require \"tango/fs\"\nputs File.read(\"measurements.txt\")\n")

    loaded = Tango::Frontend::SourceGraph::Loader.load(entry, Tango::Frontend::SourceGraph::DISK_RESOLVER)

    loaded.diagnostics.should be_empty
    package = File.join(Tango::Workspace::Layout.bundled_packages_dir, "tango", "fs.tn")
    loaded.should be_a(Tango::Frontend::Result)
    loaded.source.files.map(&.path).should eq([package, "/virtual/main.tn"])
    loaded.source.edges.map(&.request).should eq(["tango/fs"])
  end

  it "expands unsaved wildcard overlays in stable lexical order" do
    resolver = Tango::Frontend::SourceGraph.resolver({
      "/virtual/support/nested/zeta.tn" => "def zeta : Int32\n  2\nend\n",
      "/virtual/support/alpha.tn"       => "def alpha : Int32\n  1\nend\n",
    })
    entry = Tango::Source::File.new("/virtual/main.tn", "require \"./support/**\"\nputs alpha + zeta\n")

    loaded = Tango::Frontend::SourceGraph::Loader.load(entry, resolver)

    loaded.diagnostics.should be_empty
    loaded.source.files.map(&.path).should eq([
      "/virtual/support/alpha.tn",
      "/virtual/support/nested/zeta.tn",
      "/virtual/main.tn",
    ])
    loaded.source.edges.map(&.to).should eq([
      "/virtual/support/alpha.tn",
      "/virtual/support/nested/zeta.tn",
    ])
  end

  it "uses open-buffer content without changing local path resolution" do
    dependency_path = File.expand_path("/virtual/dependency.tn")
    resolver = Tango::Frontend::SourceGraph.resolver({
      dependency_path => "def answer : Int32\n  7\nend\n",
    })
    entry = Tango::Source::File.new("/virtual/main.tn", "require \"./dependency\"\nputs answer\n")

    loaded = Tango::Frontend::SourceGraph::Loader.load(entry, resolver)

    loaded.diagnostics.should be_empty
    loaded.source.files.map(&.path).should eq([dependency_path, "/virtual/main.tn"])
    loaded.source.files.first.code.should contain("  7")
    loaded.source.edges.map(&.request).should eq(["./dependency"])
  end

  it "loads transitive Tango files dependency-first and blanks consumed requires" do
    files = {
      {"main.tn", "./math"}    => Tango::Source::File.new("math.tn", "require \"./counter\"\ndef add : Int32\n  5\nend\n", "math"),
      {"math.tn", "./counter"} => Tango::Source::File.new("counter.tn", "class Counter\nend\n", "counter"),
    }
    resolver = Tango::Frontend::SourceGraph::Resolver.new do |request, from|
      files[{from.path, request}]?.try { |file| [file] } || [] of Tango::Source::File
    end
    entry = Tango::Source::File.new("main.tn", "require \"./math\"\nputs add\n", "main")

    loaded = Tango::Frontend::SourceGraph::Loader.load(entry, resolver)

    loaded.diagnostics.should be_empty
    loaded.source.files.map(&.path).should eq(["counter.tn", "math.tn", "main.tn"])
    loaded.source.edges.map { |edge| {edge.from, edge.to} }.should eq([
      {"main.tn", "math.tn"},
      {"math.tn", "counter.tn"},
    ])
    semantic = loaded.source.semantic_code(entry)
    semantic.bytesize.should eq(entry.code.bytesize)
    semantic.lines.first.should eq("                ")
    semantic.lines.last.should eq("puts add")
  end
end
