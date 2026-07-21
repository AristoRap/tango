require "../spec_helper"
require "../../src/tango/cli"
require "../../src/tango/cli/semantic_transport"

private def run_cli(argv : Array(String), stdin : String = "") : {Int32, String, String}
  input = IO::Memory.new(stdin)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Tango::CLI.run(argv, input, output, error)
  {status, output.to_s, error.to_s}
end

private def run_semantic_producer(argv : Array(String), stdin : String = "") : {Int32, String, String}
  input = IO::Memory.new(stdin)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Tango::CLI::SemanticTransport::Producer.run(argv, input, output, error)
  {status, output.to_s, error.to_s}
end

private def run_semantic_consumer(argv : Array(String), stdin : String = "") : {Int32, String, String}
  input = IO::Memory.new(stdin)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Tango::CLI::SemanticTransport::Consumer.run(argv, input, output, error)
  {status, output.to_s, error.to_s}
end

private def with_cli_env(key : String, value : String?, &)
  previous = ENV[key]?

  if value
    ENV[key] = value
  else
    ENV.delete(key)
  end

  yield
ensure
  if previous
    ENV[key] = previous
  else
    ENV.delete(key)
  end
end

private def with_cli_fake_toolchain(name : String, gofmt_script : String, go_script : String? = nil, &)
  root = File.join(Tango::Workspace::Layout.cache_dir, "spec-cli-#{name}-#{Process.pid}-#{Random.rand(100_000)}")
  Dir.mkdir_p(root)

  go_path = File.join(root, "go")
  gofmt_path = File.join(root, "gofmt")

  File.write(go_path, go_script || "#!/bin/sh\nif [ \"$1\" = \"version\" ]; then echo \"go version go1.26.4 darwin/arm64\"; exit 0; fi\nexit 1\n")
  File.write(gofmt_path, gofmt_script)
  File.chmod(go_path, 0o755)
  File.chmod(gofmt_path, 0o755)

  with_cli_env("TANGO_GO", go_path) do
    yield
  end
end

describe "tango help" do
  it "leads with the binary version and keeps implementation surfaces out of ordinary help" do
    status, out, err = run_cli(["help"])

    status.should eq(0)
    out.lines.first.should eq("Tango #{Tango::VERSION}")
    out.should contain("run          Compile and run a Tango program")
    out.should contain("build        Compile a Tango executable")
    out.should contain("fmt          Format Tango source files")
    out.should contain("--version")
    out.should_not contain("frontend")
    out.should_not contain("core")
    out.should_not contain("internal")
    out.should_not contain("bootstrap")
    out.should_not contain("prelude")
    out.should_not contain("emit")
    out.should_not contain("dump")
    out.should_not contain("lsp")
    err.should be_empty
  end

  it "shows developer commands only when explicitly requested" do
    status, out, err = run_cli(["help", "--all"])

    status.should eq(0)
    out.should contain("Developer and editor commands:")
    out.should contain("emit")
    out.should contain("dump")
    out.should contain("lsp")
    out.should_not contain("frontend")
    out.should_not contain("core")
    err.should be_empty
  end

  it "reports the compiled binary version through conventional flags" do
    ["--version", "-V", "version"].each do |argument|
      status, out, err = run_cli([argument])

      status.should eq(0)
      out.should eq("tango #{Tango::VERSION}\n")
      err.should be_empty
    end
  end
end

describe "tango semantic transport" do
  it "round-trips stdin through the canonical bundle stream" do
    status, bundle, err = run_semantic_producer(["-", "--emit-semantic", "-"], "puts 1\n")

    status.should eq(0)
    err.should be_empty
    document = Tango::Frontend::Bundle::Codec.load(bundle)
    document.frontend_version.should eq("tango/#{Tango::VERSION} crystal/#{Crystal::VERSION}")
    document.prelude_version.should eq("tango/#{Tango::VERSION}")

    with_cli_fake_toolchain("bundle-stream", "#!/bin/sh\ncat\n") do
      status, transported, err = run_semantic_consumer(["-", "--emit-go"], bundle)
      ordinary_status, ordinary, ordinary_err = run_cli(["emit", "go", "-"], "puts 1\n")

      status.should eq(0)
      ordinary_status.should eq(0)
      transported.should eq(ordinary)
      err.should be_empty
      ordinary_err.should be_empty
    end
  end

  it "writes a file bundle atomically and applies the requested core profile" do
    root = File.join(Dir.tempdir, "tango-semantic-transport-#{Process.pid}-#{Random.rand(100_000)}")
    bundle_path = File.join(root, "program.json")
    Dir.mkdir_p(root)

    begin
      status, out, err = run_semantic_producer([
        File.join("examples", "weather_report.tn"),
        "--emit-semantic",
        bundle_path,
      ])
      status.should eq(0)
      out.should be_empty
      err.should be_empty
      File.file?(bundle_path).should be_true
      Dir.glob("#{bundle_path}.tmp-*").should be_empty

      with_cli_fake_toolchain("bundle-profile", "#!/bin/sh\ncat\n") do
        development_status, development, development_err = run_semantic_consumer([bundle_path, "--emit-go"])
        release_status, release, release_err = run_semantic_consumer(["--release", bundle_path, "--emit-go"])

        development_status.should eq(0)
        release_status.should eq(0)
        development.should_not eq(release)
        development_err.should be_empty
        release_err.should be_empty
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "carries frontend failures for the consumer to render" do
    status, bundle, err = run_semantic_producer(["-", "--emit-semantic", "-"], "puts(\n")

    status.should eq(0)
    err.should be_empty

    status, out, err = run_semantic_consumer(["-", "--emit-go"], bundle)
    status.should eq(1)
    out.should be_empty
    err.should contain("error:")
    err.should contain("1 | puts(")
    err.should_not contain("Unhandled exception")
  end

  it "rejects unsupported and malformed bundles without an exception trace" do
    status, out, err = run_semantic_consumer(["-", "--emit-go"], %({"schema_version":2,"future":true}))
    status.should eq(1)
    out.should be_empty
    err.should contain("unsupported semantic bundle schema version 2")
    err.should_not contain("Unhandled exception")

    status, out, err = run_semantic_consumer(["-", "--emit-go"], %({"schema_version":1))
    status.should eq(1)
    out.should be_empty
    err.should contain("invalid semantic bundle at $")
    err.should_not contain("Unhandled exception")
  end

  it "rejects incomplete command shapes without reading or writing files" do
    status, out, err = run_semantic_producer(["examples/puts.tn"])
    status.should eq(1)
    out.should be_empty
    err.should contain(Tango::CLI::SemanticTransport::Producer::USAGE)

    status, out, err = run_semantic_consumer(["missing.json"])
    status.should eq(1)
    out.should be_empty
    err.should contain(Tango::CLI::SemanticTransport::Consumer::USAGE)
    err.should_not contain("missing.json")
  end
end

describe "tango fmt" do
  it "formats stdin to stdout and checks stdin without rewriting its stream" do
    status, out, err = run_cli(["fmt", "-"], "if true\nputs(  1 )\nend")
    status.should eq(0)
    out.should eq("if true\n  puts(1)\nend\n")
    err.should be_empty

    status, out, err = run_cli(["fmt", "--check", "-"], "puts( 1 )")
    status.should eq(1)
    out.should be_empty
    err.should contain("stdin.tn is not formatted")

    status, out, err = run_cli(["fmt", "--check", "-"], "puts(1)\n")
    status.should eq(0)
    out.should be_empty
    err.should be_empty
  end

  it "formats recursive and explicit inputs once in stable order" do
    root = File.join(Dir.tempdir, "tango-fmt-batch-#{Process.pid}-#{Random.rand(100_000)}")
    nested = File.join(root, "nested")
    first = File.join(root, "first.tn")
    second = File.join(nested, "second.tn")
    explicit = File.join(root, "extensionless")
    Dir.mkdir_p(nested)
    File.write(first, "puts(  1 )")
    File.write(second, "puts(  2 )")
    File.write(explicit, "puts(  3 )")

    begin
      status, out, err = run_cli(["fmt", root, first, explicit])

      status.should eq(0)
      out.lines.count { |line| line.includes?(first) }.should eq(1)
      out.should contain("formatted #{second}")
      out.should contain("formatted #{explicit}")
      File.read(first).should eq("puts(1)\n")
      File.read(second).should eq("puts(2)\n")
      File.read(explicit).should eq("puts(3)\n")
      err.should be_empty
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "discovers .tn files beneath the current directory when paths are omitted" do
    root = File.join(Dir.tempdir, "tango-fmt-cwd-#{Process.pid}-#{Random.rand(100_000)}")
    path = File.join(root, "main.tn")
    Dir.mkdir_p(root)
    File.write(path, "puts(  1 )")

    begin
      Dir.cd(root) do
        status, out, err = run_cli(["fmt"])
        status.should eq(0)
        out.should contain("formatted ./main.tn")
        err.should be_empty
      end
      File.read(path).should eq("puts(1)\n")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "checks every file without writing and reports non-canonical input" do
    root = File.join(Dir.tempdir, "tango-fmt-check-#{Process.pid}-#{Random.rand(100_000)}")
    changed = File.join(root, "changed.tn")
    clean = File.join(root, "clean.tn")
    Dir.mkdir_p(root)
    File.write(changed, "puts(  1 )")
    File.write(clean, "puts(2)\n")

    begin
      status, out, err = run_cli(["fmt", "--check", root])
      status.should eq(1)
      out.should be_empty
      err.should contain("#{changed} is not formatted")
      err.should_not contain("#{clean} is not formatted")
      File.read(changed).should eq("puts(  1 )")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "preflights the complete batch before writing any file" do
    root = File.join(Dir.tempdir, "tango-fmt-transaction-#{Process.pid}-#{Random.rand(100_000)}")
    changed = File.join(root, "changed.tn")
    broken = File.join(root, "broken.tn")
    Dir.mkdir_p(root)
    File.write(changed, "puts(  1 )")
    File.write(broken, "if")

    begin
      status, out, err = run_cli(["fmt", root])
      status.should eq(1)
      out.should be_empty
      err.should contain("unexpected token: EOF")
      err.should contain("--> #{broken}:1:3")
      File.read(changed).should eq("puts(  1 )")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "contains invalid UTF-8 and rejects missing paths and mixed stdin" do
    root = File.join(Dir.tempdir, "tango-fmt-errors-#{Process.pid}-#{Random.rand(100_000)}")
    invalid = File.join(root, "invalid.tn")
    Dir.mkdir_p(root)
    File.write(invalid, Bytes[0xfe_u8, 0xff_u8])

    begin
      status, out, err = run_cli(["fmt", invalid])
      status.should eq(1)
      out.should be_empty
      err.should contain("not valid UTF-8")
      err.should_not contain("Unhandled exception")

      status, out, err = run_cli(["fmt", File.join(root, "missing")])
      status.should eq(1)
      out.should be_empty
      err.should contain("file or directory does not exist")

      status, out, err = run_cli(["fmt", "-", invalid], "puts 1")
      status.should eq(1)
      out.should be_empty
      err.should contain("'-' must be the only formatting path")
    ensure
      FileUtils.rm_rf(root)
    end
  end
end

describe "tango emit" do
  it "prints gofmt-clean Go source" do
    formatted = <<-GO
    package main

    import "fmt"

    func main() {
    \tfmt.Println(1)
    }
    GO

    with_cli_fake_toolchain("emit", "#!/bin/sh\ncat >/dev/null\nprintf '%s' '#{formatted}'\n") do
      status, out, err = run_cli(["emit", "go", "--release", "-"], "puts 1")

      status.should eq(0)
      out.should eq(formatted)
      err.should be_empty
    end
  end
end

describe "tango run" do
  it "preserves eager exception order in development and release collection pipelines" do
    source = <<-TANGO
      values = ["1.5", "bad", 1]
      puts values.select { |value| value.as(String).to_f > 0.0 }.map { |value| value.as(Int32) }.reduce(0) { |sum, value| sum + value }
      TANGO

    development = run_cli(["run", "-"], source)
    release = run_cli(["run", "--release", "-"], source)

    development[0].should eq(1)
    release[0].should eq(1)
    development[2].should contain(%(Invalid Float64: "bad"))
    release[2].should contain(%(Invalid Float64: "bad"))
    release[2].should_not contain("cast from")
  end

  it "rejects unknown flags and multiple source paths before reading files" do
    [
      ["run", "--unknown"],
      ["run", "first.tn", "second.tn"],
      ["build", "first.tn", "second.tn"],
      ["emit", "go", "first.tn", "second.tn"],
      ["dump", "nir", "first.tn", "second.tn"],
    ].each do |argv|
      status, out, err = run_cli(argv)
      status.should eq(1)
      out.should be_empty
      err.should_not contain("Unhandled exception")
      err.should match(/unknown option|multiple source files/)
    end
  end

  it "reports an unreadable entrypoint without an exception trace" do
    status, out, err = run_cli(["run", "/definitely/missing/tango-entry.tn"])

    status.should eq(1)
    out.should be_empty
    err.should contain("tango: file operation failed")
    err.should_not contain("Unhandled exception")
  end

  it "preserves whitespace-split cardinality in release" do
    source = %(puts "  alpha\\u{00a0}beta\\t gamma  ".split.size\nputs " \\t\\n ".split.size\n)
    status, out, err = run_cli(["run", "--release", "-"], source)

    status.should eq(0)
    out.should eq("3\n0\n")
    err.should be_empty
  end

  it "rejects cwd-relative requires from stdin" do
    status, out, err = run_cli(["run", "-"], "require \"./examples/puts\"\n")

    status.should eq(1)
    out.should be_empty
    err.should contain("relative requires from stdin need a named entry file")
    err.should contain("require \"./examples/puts\"")
  end

  it "uses the recursive source graph across run, build, emit, and every dump" do
    entry = File.join("examples", "require_graph.tn")
    output_path = File.join(Dir.tempdir, "tango-source_graph_matrix-#{Process.pid}-#{Random.rand(100_000)}")

    begin
      status, out, err = run_cli(["run", "--release", entry])
      status.should eq(0)
      out.should eq("10\n2\n")
      err.should be_empty

      status, out, err = run_cli(["build", "--release", entry, "-o", output_path])
      status.should eq(0)
      out.should be_empty
      err.should be_empty
      File.file?(output_path).should be_true

      status, out, err = run_cli(["emit", "go", entry])
      status.should eq(0)
      out.should contain("func combined_Point")
      out.should contain("func scale_Int32")
      err.should be_empty

      %w(nir facts plans lir).each do |phase|
        status, out, err = run_cli(["dump", phase, "--release", entry])
        status.should eq(0)
        out.should start_with(%(source_graph entry="#{entry}"))
        out.should contain(%(request="./support/require_graph/**"))
        out.should_not match(/\bRequire\b/)
        err.should be_empty
      end
    ensure
      File.delete(output_path) if File.exists?(output_path)
    end
  end

  it "renders a typed go vet failure at the CLI boundary" do
    go_script = <<-SH
    #!/bin/sh
    if [ "$1" = "version" ]; then
      echo "go version go1.26.4 darwin/arm64"
      exit 0
    fi
    if [ "$1" = "vet" ]; then
      echo "$2:3:2: fake emitter check failure" >&2
      exit 1
    fi
    exit 99
    SH

    with_cli_fake_toolchain("run-vet", "#!/bin/sh\ncat\n", go_script) do
      status, out, err = run_cli(["run", "-"], "puts 1")

      status.should eq(1)
      out.should be_empty
      err.should contain("main.go:3:2: error: fake emitter check failure")
      err.should_not contain("Unhandled exception")
    end
  end
end

describe "tango doctor" do
  it "explains the resolved frontend, prelude, Go toolchain, version, and caches" do
    with_cli_fake_toolchain("doctor", "#!/bin/sh\nif [ \"$1\" = \"version\" ]; then echo \"go version go1.26.4 darwin/arm64\"; exit 0; fi\nexit 1\n") do
      status, out, err = run_cli(["doctor"])

      status.should eq(0)
      out.should contain("tango doctor — environment check")
      out.should contain("Crystal compiler")
      out.should contain("Crystal sources")
      out.should contain("Tango prelude")
      out.should contain("Go toolchain")
      out.should contain("Go version")
      out.should contain("Local caches")
      out.should contain("go1.26")
      err.should be_empty
    end
  end

  it "exposes machine-readable Go resolver probes" do
    with_cli_fake_toolchain("doctor-probes", "#!/bin/sh\nexit 1\n") do
      status, out, err = run_cli(["doctor", "--go-path"])
      status.should eq(0)
      out.should contain("spec-cli-doctor-probes")
      err.should be_empty

      status, out, err = run_cli(["doctor", "--go-min"])
      status.should eq(0)
      out.should eq("#{Tango::Toolchain::Go::MIN_VERSION[0]}.#{Tango::Toolchain::Go::MIN_VERSION[1]}\n")
      err.should be_empty
    end
  end

  it "keeps failed checks as shared diagnostic data" do
    with_cli_env("TANGO_GO", "/definitely/missing/tango-go") do
      report = Tango::CLI::Doctor.inspect
      diagnostic = report.diagnostics.find! { |item| item.code == Tango::Diagnostics::CHECK_GO }

      diagnostic.origin.check?.should be_true
      diagnostic.message.should contain("no file exists")

      status, out, err = run_cli(["doctor"])
      status.should eq(1)
      out.should contain("error Go toolchain")
      out.should contain("no file exists")
      err.should be_empty
    end
  end

  it "diagnoses a missing absolute Crystal source path" do
    with_cli_env("CRYSTAL_PATH", "/definitely/missing/crystal-src") do
      report = Tango::CLI::Doctor.inspect
      diagnostic = report.diagnostics.find! { |item| item.code == Tango::Diagnostics::CHECK_CRYSTAL_PATH }

      diagnostic.message.should contain("missing absolute path entries")
    end
  end
end

describe "tango clean" do
  it "removes only the current workspace's generated .tango tree and is idempotent" do
    root = File.join(Dir.tempdir, "tango-clean-#{Process.pid}-#{Random.rand(100_000)}")
    generated = File.join(root, ".tango", "cache", "artifact")
    kept = File.join(root, "keep.txt")
    Dir.mkdir_p(File.dirname(generated))
    File.write(generated, "generated")
    File.write(kept, "source")

    begin
      Dir.cd(root) do
        generated_root = File.join(Dir.current, ".tango")
        status, out, err = run_cli(["clean"])
        status.should eq(0)
        out.should contain("removed #{generated_root}")
        err.should be_empty
        File.exists?(generated).should be_false
        File.exists?(kept).should be_true

        status, out, err = run_cli(["clean"])
        status.should eq(0)
        out.should contain("already clean")
        err.should be_empty
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end
end

describe "tango dump" do
  it "renders dependency diagnostics from the matching source file" do
    fixtures = File.join("spec", "fixtures", "source_graph_diagnostics")
    cases = [
      {"type_error", "dependency.tn", "value + 1"},
      {"missing_nested", "middle.tn", "require \"./absent\""},
      {"syntax_error", "dependency.tn", "unexpected token: EOF"},
      {"top_level", "dependency.tn", "puts \"loading\""},
      {"unsupported", "dependency.tn", "value = if true"},
    ]

    cases.each do |kind, filename, excerpt|
      entry = File.join(fixtures, kind, "main.tn")
      dependency = File.expand_path(File.join(fixtures, kind, filename))
      status, out, err = run_cli(["dump", "lir", entry])

      status.should eq(1)
      out.should be_empty unless kind == "unsupported"
      err.should contain("--> #{dependency}:")
      err.should contain(excerpt)
      err.should_not contain("In #{entry}:")
    end
  end

  it "dumps nir for puts 1" do
    status, out, err = run_cli(["dump", "nir", "-"], "puts 1")

    status.should eq(0)
    out.should contain("Call")
    out.should contain("IntLiteral")
    err.should be_empty
  end

  it "renders unused-local warnings while exposing the discard in LIR" do
    status, out, err = run_cli(["dump", "lir", "-"], "stale = 7\nputs 1\n")

    status.should eq(0)
    out.should contain("Discard IntConst Int32 7")
    err.should contain("unused local variable 'stale' — assigned but never read")
  end

  it "dumps assignments, locals, and if branches" do
    source = <<-TN
      x = 1
      if true
        puts x
      else
        puts 2
      end
      TN

    status, out, err = run_cli(["dump", "nir", "-"], source)

    status.should eq(0)
    out.should contain("Assign")
    out.should contain("Local x")
    out.should contain("If")
    out.should contain("Block")
    out.should contain("BoolLiteral true")
    err.should be_empty
  end

  it "dumps defs, params, and classes" do
    source = <<-TN
      class Foo
      end
      def foo(x : Int32) : Int32
        x
      end
      puts foo(1)
      TN

    status, out, err = run_cli(["dump", "nir", "-"], source)

    status.should eq(0)
    out.should contain("Class Foo")
    out.should contain("Def foo")
    out.should contain("Param x")
    err.should be_empty
  end

  it "lowers a bare local assignment through the full phase chain" do
    status, out, err = run_cli(["dump", "lir", "-"], "x = 1\nputs x")

    status.should eq(0)
    out.should contain("Assign")
    err.should be_empty
  end

  it "renders a closure's body indented beneath it, not just its params" do
    source = <<-TN
      def twice(&block : Int32 -> Int32) : Int32
        block.call(block.call(1))
      end

      captured = 10
      puts twice { |n| n + captured }
      TN

    status, out, err = run_cli(["dump", "lir", "-"], source)

    status.should eq(0)
    out.should contain("Closure (n)\n  AbruptExit Return CheckedArithmetic Add Int32 WideningRoundTrip Temp n Temp captured")
    err.should be_empty
  end

  it "fails loudly instead of sending unsupported programs to codegen" do
    # A symbol literal is unsupported surface (a bare `nil` is now the
    # standalone `Nil` unit value and lowers cleanly, so it no longer serves
    # as the "unsupported" case here).
    source = <<-TN
      x = 1
      y = :sym
      TN

    status, out, err = run_cli(["dump", "lir", "-"], source)

    status.should eq(1)
    out.should contain("Discard")
    out.should contain("UnsupportedValue")
    err.should contain("unsupported value")
  end

  it "dumps facts for puts 1" do
    status, out, err = run_cli(["dump", "facts", "-"], "puts 1")

    status.should eq(0)
    out.should contain("go_external fmt.Println")
    err.should be_empty
  end

  it "dumps plans for puts 1" do
    status, out, err = run_cli(["dump", "plans", "-"], "puts 1")

    status.should eq(0)
    out.should contain("call ExternalGo")
    err.should be_empty
  end

  it "dumps lir for puts 1" do
    status, out, err = run_cli(["dump", "lir", "-"], "puts 1")

    status.should eq(0)
    out.should eq(<<-DUMP + '\n')
      source_graph entry="stdin.tn"
      source_graph files=["stdin.tn"]
      UncaughtException CrystalStyle
      ExternalCall IntConst Int32 1 @stdin.tn:1:1
      DUMP
    err.should be_empty
  end

  it "dumps lowering seam traces for nir and lir" do
    status, out, err = run_cli(["dump", "nir", "--trace", "-"], "def id(x)\n  x\nend\nputs id(1)")

    status.should eq(0)
    out.should contain(%(decision="internal-call" lowered="id_Int32"))
    err.should be_empty

    status, out, err = run_cli(["dump", "lir", "--trace", "-"], "def id(x)\n  x\nend\nputs id(1)")

    status.should eq(0)
    out.should contain("(func name=\"id_Int32\" return=\"Int32\"")
    out.should contain("(call name=\"id_Int32\"")
    err.should be_empty
  end

  it "rejects trace mode for non-lowering dump targets" do
    status, out, err = run_cli(["dump", "facts", "--trace", "-"], "puts 1")

    status.should eq(1)
    out.should be_empty
    err.should contain("--trace is only supported")
  end

  it "rejects an unknown dump target" do
    status, out, err = run_cli(["dump", "bogus", "-"], "puts 1")

    status.should eq(1)
    out.should be_empty
    err.should contain("usage: tango dump")
  end

  it "rejects a missing dump target" do
    status, _, err = run_cli(["dump"], "puts 1")

    status.should eq(1)
    err.should contain("usage: tango dump")
  end

  it "surfaces diagnostics instead of dumping a broken program" do
    status, out, err = run_cli(["dump", "nir", "-"], "puts(")

    status.should eq(1)
    out.should be_empty
    err.should contain("error:")
    err.should contain("--> stdin.tn:1:")
    err.should contain("1 | puts(")
    err.should_not contain("In src/")
  end

  it "renders compile errors for normal product commands without an exception trace" do
    status, out, err = run_cli(["run", "-"], "puts(")

    status.should eq(1)
    out.should be_empty
    err.should contain("error:")
    err.should contain("1 | puts(")
    err.should_not contain("Unhandled exception")
  end
end
