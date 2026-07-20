require "../spec_helper"

describe Tango::Compiler::Snapshot do
  it "captures every compiler phase for a simple program" do
    snapshot = Tango.snapshot("puts 1", filename: "probe.cr")

    snapshot.nir.should_not be_nil
    snapshot.facts.should_not be_nil
    snapshot.plans.should_not be_nil
    snapshot.lir.should_not be_nil
    snapshot.target_ir.should_not be_nil
    snapshot.go_source.to_s.should contain("fmt.Println(int32(1))")
    snapshot.editor_index.occurrences.should_not be_empty
  end

  it "can stop before target translation for editor requests" do
    snapshot = Tango.pre_target_snapshot("puts 1", filename: "probe.cr")

    snapshot.nir.should_not be_nil
    snapshot.facts.should_not be_nil
    snapshot.lir.should_not be_nil
    snapshot.target_ir.should be_nil
    snapshot.go_source.should be_nil
    snapshot.editor_index.occurrences.should_not be_empty
  end

  it "keeps frontend errors as snapshot diagnostics" do
    snapshot = Tango.snapshot("puts(", filename: "broken.cr")

    snapshot.go_source.should be_nil
    snapshot.diagnostics.should_not be_empty
  end

  it "compiles functions and classes from transitive Tango requires" do
    files = {
      {"main.tn", "./math"} => Tango::Source::File.new(
        "math.tn",
        "require \"./counter\"\ndef add(a : Int32, b : Int32) : Int32\n  a + b\nend\n",
        "math"
      ),
      {"math.tn", "./counter"} => Tango::Source::File.new(
        "counter.tn",
        "class Counter\n  getter value : Int32\n  def initialize(@value : Int32)\n  end\nend\n",
        "counter"
      ),
    }
    resolver = Tango::Frontend::SourceGraph::Resolver.new do |request, from|
      files[{from.path, request}]?.try { |file| [file] } || [] of Tango::Source::File
    end
    source = "require \"./math\"\nputs add(2, 3)\nputs Counter.new(7).value\n"

    snapshot = Tango.pre_target_snapshot(source, filename: "main.tn", resolver: resolver)

    snapshot.diagnostics.should be_empty
    snapshot.source.files.map(&.path).should eq(["counter.tn", "math.tn", "main.tn"])
    snapshot.nir.should_not be_nil
    snapshot.editor_index.declarations.any? { |decl| decl.name == "add" && decl.range.path == "math.tn" }.should be_true
    snapshot.editor_index.declarations.any? { |decl| decl.name == "Counter" && decl.range.path == "counter.tn" }.should be_true
  end

  it "rejects executable top-level code in a required file" do
    dependency = Tango::Source::File.new(
      "dependency.tn",
      "puts \"loading\"\ndef answer : Int32\n  41\nend\n",
      "dependency"
    )
    resolver = Tango::Frontend::SourceGraph::Resolver.new do |request, _from|
      request == "./dependency" ? [dependency] : [] of Tango::Source::File
    end

    snapshot = Tango.pre_target_snapshot(
      "require \"./dependency\"\nputs answer\n",
      filename: "main.tn",
      resolver: resolver
    )

    snapshot.nir.should be_nil
    diagnostic = snapshot.diagnostics.find!(&.code.==(Tango::Diagnostics::FRONT_REQUIRE_TOP_LEVEL))
    diagnostic.file.should eq("dependency.tn")
    diagnostic.line.should eq(1)
    diagnostic.message.should contain("definitions-only")
  end

  it "underlines the requested path in a missing local require diagnostic" do
    source = "require \"./definitely_missing\"\n"
    snapshot = Tango.pre_target_snapshot(source, filename: "missing_require.tn")
    diagnostic = snapshot.diagnostics.first

    diagnostic.origin.frontend?.should be_true
    diagnostic.file.should eq("missing_require.tn")
    diagnostic.line.should eq(1)
    diagnostic.column.should eq(9)
    diagnostic.size.should eq(22)
    diagnostic.range.should_not be_nil
    diagnostic.message.should contain("can't find file './definitely_missing'")

    rendered = Tango::Diagnostics::Renderer.render(source, diagnostic, path: "missing_require.tn")
    rendered.should contain("|         ^^^^^^^^^^^^^^^^^^^^")
  end

  it "keeps a macro type error at Crystal's invocation location" do
    source = "macro wrong\n  1 + \"x\"\nend\nwrong\n"
    diagnostic = Tango.pre_target_snapshot(source, filename: "macro_error.tn").diagnostics.first

    diagnostic.origin.frontend?.should be_true
    diagnostic.file.should eq("macro_error.tn")
    diagnostic.line.should eq(1)
    diagnostic.column.should eq(7)
    diagnostic.size.should eq(1)
    diagnostic.range.should_not be_nil
    diagnostic.message.should contain("expected argument #1 to 'Int32#+' to be Float64 or Int32, not String")
  end

  it "renders a frontend free function without Crystal's root qualifier" do
    source = "def maybe : Int32?\n  \"x\"\nend\nmaybe\n"
    diagnostic = Tango.pre_target_snapshot(source, filename: "nilable_return_error.tn").diagnostics.first

    diagnostic.message.should eq("method maybe must return (Int32 | Nil) but it is returning String")
    diagnostic.detail.to_s.should contain("method ::maybe must return (Int32 | Nil) but it is returning String")
  end

  it "requires typed declarations for every accessor macro" do
    %w(getter setter property).each do |macro_name|
      source = "class Settings\n  #{macro_name} name\nend\n"
      snapshot = Tango.pre_target_snapshot(source, filename: "untyped_#{macro_name}.tn")
      diagnostic = snapshot.diagnostics.first

      snapshot.nir.should be_nil
      diagnostic.origin.frontend?.should be_true
      diagnostic.file.should eq("untyped_#{macro_name}.tn")
      diagnostic.message.should contain("tango accessors require a type declaration")
      diagnostic.message.should contain("#{macro_name} x : T")
    end
  end

  it "does not mistake compiler-generated internal plumbing for user calls" do
    sources = [
      "xs = [1, 2]\nputs xs.size\n",
      "ch = Channel(Int32).new\nselect\nwhen value = ch.receive\n  puts value\nend\n",
      "value = 7\nputs \"value=\#{value}\"\n",
    ]

    sources.each_with_index do |source, index|
      snapshot = Tango.pre_target_snapshot(source, filename: "internal_expansion_#{index}.tn")

      snapshot.diagnostics.none? { |diagnostic| diagnostic.code == Tango::Diagnostics::INTERNAL_RESERVED }.should be_true
    end
  end

  it "locates an instantiated type error at its actionable inner frame" do
    source = <<-TN
      class Point
        def initialize(x : Int32)
          @x = x
        end
      end

      def find(hit : Bool) : Point?
        if hit
          Point.new("7")
        else
          nil
        end
      end

      p = find(true)
      TN
    diagnostic = Tango.pre_target_snapshot(source, filename: "nested_error.tn").diagnostics.first

    diagnostic.line.should eq(9)
    diagnostic.column.should eq(15)
    diagnostic.size.should eq(3)
    diagnostic.range.should_not be_nil
    diagnostic.message.should contain("expected argument #1 to 'Point.new' to be Int32, not String")
    diagnostic.detail.to_s.should contain("instantiating 'find(Bool)'")

    rendered = Tango::Diagnostics::Renderer.render(source, diagnostic, path: "nested_error.tn")
    rendered.should contain("Point.new(\"7\")")
    rendered.should contain("^^^")
  end

  it "locates a deferred value-block break diagnostic" do
    source = <<-TN
      def value_each(& : Int32 -> Int32) : Int32
        yield 1
      end

      value_each do |n|
        break
        n
      end
      TN
    diagnostic = Tango.pre_target_snapshot(source, filename: "value_break.tn").diagnostics.first

    diagnostic.origin.emit?.should be_true
    diagnostic.line.should eq(6)
    diagnostic.column.should eq(3)
    diagnostic.range.should_not be_nil
    diagnostic.message.should contain("union-typed block lowering")
  end

  it "keeps an unsupported value expression at its own source location" do
    source = <<-TN
      puts 0
      x = if true
        puts 1
        2
      else
        3
      end
      puts x
      TN
    diagnostic = Tango.pre_target_snapshot(source, filename: "unsupported_if_value.tn").diagnostics.find!(&.origin.emit?)

    diagnostic.file.should eq("unsupported_if_value.tn")
    diagnostic.line.should eq(2)
    diagnostic.column.should eq(5)
    diagnostic.range.should_not be_nil
    diagnostic.message.should contain("unsupported multi-statement if value")
  end

  it "rejects mixed Bool-union truthiness at the condition" do
    source = <<-TN
      def maybe_bool(flag : Bool) : Bool?
        flag ? false : nil
      end
      if maybe_bool(true)
        puts 1
      end
      TN
    diagnostic = Tango.pre_target_snapshot(source, filename: "bool_union_condition.tn").diagnostics.find!(&.origin.emit?)

    diagnostic.file.should eq("bool_union_condition.tn")
    diagnostic.line.should eq(4)
    diagnostic.column.should eq(4)
    diagnostic.range.should_not be_nil
    diagnostic.message.should contain("truthiness for a union containing Bool")
  end

  it "rejects a non-comparable hash key at the hash construction site" do
    snapshot = Tango.snapshot("h = Hash(Proc(Nil), Int32).new\n", filename: "bad_hash.tn")
    diagnostic = snapshot.diagnostics.find!(&.origin.emit?)

    diagnostic.origin.emit?.should be_true
    diagnostic.line.should eq(1)
    diagnostic.column.should eq(5)
    diagnostic.range.should_not be_nil
    diagnostic.message.should contain("hash key () -> Nil cannot use native equality")
    diagnostic.message.should contain("function values only compare to nil")
  end
end

describe Tango::Compiler::Pipeline do
  it "exposes phase artifacts through its current Snapshot without mirroring them" do
    pipeline = Tango::Compiler::Pipeline.new
    snapshot = pipeline.snapshot("puts 1", filename: "pipeline_probe.tn")

    pipeline.current_snapshot.should be(snapshot)
    pipeline.nir.should be(snapshot.nir)
    pipeline.facts.should be(snapshot.facts)
    pipeline.plans.should be(snapshot.plans)
    pipeline.lir.should be(snapshot.lir)
    pipeline.go.should be(snapshot.target_ir)

    pre_target = pipeline.pre_target_snapshot("puts 2", filename: "pipeline_pre_target_probe.tn")
    pipeline.current_snapshot.should be(pre_target)
    pipeline.go.should be_nil
  end

  it "builds editor-only and source-graph failure snapshots through the neutral frontend result" do
    pipeline = Tango::Compiler::Pipeline.new
    source = "def answer : Int32\n  42\nend\n"

    surface = pipeline.editor_surface_snapshot(source, filename: "surface_result.tn")

    surface.nir.should be_nil
    surface.diagnostics.should be_empty
    surface.syntax_surface.declarations.map(&.name).should contain("answer")

    failed = pipeline.pre_target_snapshot(
      "require \"./missing\"\n#{source}",
      filename: "failed_result.tn"
    )

    failed.nir.should be_nil
    failed.diagnostics.first.code.should eq(Tango::Diagnostics::FRONT_REQUIRE)
    failed.syntax_surface.declarations.map(&.name).should contain("answer")
  end
end
