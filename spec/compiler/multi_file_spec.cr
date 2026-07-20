require "../spec_helper"

private SOURCE_GRAPH_DIAGNOSTIC_FIXTURES = File.join("spec", "fixtures", "source_graph_diagnostics")

private def source_graph_diagnostic_snapshot(kind : String) : Tango::Compiler::Snapshot
  entry = File.join(SOURCE_GRAPH_DIAGNOSTIC_FIXTURES, kind, "main.tn")
  Tango.snapshot(File.read(entry), filename: entry)
end

describe "multi-file compiler diagnostics" do
  it "accepts declaration annotations in a definitions-only required file" do
    files = {
      {"main.tn", "./support"} => Tango::Source::File.new(
        "support.tn",
        "@[Primitive(:tango_external)]\n@[Go(\"fmt.Println\")]\ndef print_value(value : Int32) : Nil\nend\n",
        "support"
      ),
    }
    resolver = Tango::Frontend::SourceGraph::Resolver.new do |request, from|
      files[{from.path, request}]?.try { |file| [file] } || [] of Tango::Source::File
    end

    snapshot = Tango.snapshot("require \"./support\"\nprint_value(7)\n", filename: "main.tn", resolver: resolver)

    snapshot.diagnostics.should be_empty
    expect_present(snapshot.go_source).should contain("fmt.Println(int32(7))")
  end

  it "keeps bundled operational leaves reserved from application source" do
    source = <<-TN
      require "tango/fs"
      puts __tango_file_read("measurements.txt")
      TN

    diagnostic = Tango.snapshot(source, filename: "main.tn").diagnostics.first

    diagnostic.code.should eq(Tango::Diagnostics::INTERNAL_RESERVED)
    diagnostic.message.should contain("__tango_file_read is tango-internal")
  end

  it "resolves a nested dependency type error against its actionable inner file" do
    snapshot = source_graph_diagnostic_snapshot("type_error")
    diagnostic = snapshot.diagnostics.first
    dependency = File.expand_path(File.join(SOURCE_GRAPH_DIAGNOSTIC_FIXTURES, "type_error", "dependency.tn"))

    diagnostic.file.should eq(dependency)
    diagnostic.line.should eq(2)
    diagnostic.column.should eq(11)
    diagnostic.range.should_not be_nil
    expect_present(diagnostic.range).path.should eq(dependency)
    diagnostic.message.should contain("expected argument #1 to 'String#+'")
    diagnostic.detail.to_s.should contain("instantiating 'broken(String)'")
    diagnostic.detail.to_s.should contain("type_error/dependency.tn:2:11")
  end

  it "keeps missing nested requires, dependency syntax errors, and definitions-only errors structured" do
    cases = [
      {"missing_nested", "middle.tn", 1, "\"./absent\""},
      {"syntax_error", "dependency.tn", 2, "unexpected token: EOF"},
      {"top_level", "dependency.tn", 1, "definitions-only"},
    ]

    cases.each do |kind, filename, line, message|
      diagnostic = source_graph_diagnostic_snapshot(kind).diagnostics.first
      path = File.expand_path(File.join(SOURCE_GRAPH_DIAGNOSTIC_FIXTURES, kind, filename))

      diagnostic.file.should eq(path)
      diagnostic.line.should eq(line)
      diagnostic.range.should_not be_nil
      expect_present(diagnostic.range).path.should eq(path)
      if kind == "missing_nested"
        file = File.read(path)
        range = expect_present(diagnostic.range)
        file.byte_slice(range.start_offset, range.length).should eq(message)
      else
        diagnostic.message.should contain(message)
      end
    end
  end

  it "keeps unsupported dependency work located through NIR and LIR" do
    snapshot = source_graph_diagnostic_snapshot("unsupported")
    dependency = File.expand_path(File.join(SOURCE_GRAPH_DIAGNOSTIC_FIXTURES, "unsupported", "dependency.tn"))
    diagnostic = snapshot.diagnostics.find!(&.origin.emit?)
    program = expect_present(snapshot.nir)
    lir = expect_present(snapshot.lir)
    unsupported = Tango::IR::LIR.unsupported_reasons(lir).first

    diagnostic.file.should eq(dependency)
    diagnostic.line.should eq(2)
    diagnostic.column.should eq(11)
    expect_present(diagnostic.range).path.should eq(dependency)
    definition = program.body.compact_map(&.as?(Tango::IR::NIR::Def)).first
    expect_present(definition.span).path.should eq(dependency)
    expect_present(unsupported.loc).file.should eq(dependency)
    expect_present(unsupported.loc).line.should eq(2)
  end

  it "keys identical declaration offsets by path and preserves both Go line directives" do
    snapshot = source_graph_diagnostic_snapshot("same_offset")
    first_path = File.expand_path(File.join(SOURCE_GRAPH_DIAGNOSTIC_FIXTURES, "same_offset", "first.tn"))
    second_path = File.expand_path(File.join(SOURCE_GRAPH_DIAGNOSTIC_FIXTURES, "same_offset", "second.tn"))
    first = snapshot.editor_index.declarations.find!(&.name.==("first_value"))
    second = snapshot.editor_index.declarations.find!(&.name.==("second_value"))

    first.range.start_offset.should eq(second.range.start_offset)
    snapshot.editor_index.declaration_at(first_path, first.range.start_offset).try(&.name).should eq("first_value")
    snapshot.editor_index.declaration_at(second_path, second.range.start_offset).try(&.name).should eq("second_value")

    lir = expect_present(snapshot.lir)
    function_locations = lir.functions.compact_map(&.loc).select { |loc| loc.file.in?(first_path, second_path) }
    function_locations.map(&.file).sort.should eq([first_path, second_path].sort)

    go = expect_present(snapshot.go_source)
    go.should contain("//line #{first_path}:1:1\nfunc first__value")
    go.should contain("//line #{second_path}:1:1\nfunc second__value")
  end
end
