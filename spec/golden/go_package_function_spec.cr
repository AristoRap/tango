require "../spec_helper"
require "../../src/tango/dump"

describe "Go package function interop" do
  source_path = File.join("examples", "go_package_function.tn")
  snapshot = Tango.snapshot(File.read(source_path), filename: source_path)

  it "retains import, package, symbol, and module identities through lowering" do
    facts = Tango::Dump::Facts.render(snapshot)
    facts.should contain("go_external salute.Greeting")
    facts.should contain("import=example.com/tango-fixtures/greeting/v2")
    facts.should contain("package=salute")
    facts.should contain("symbol=Greeting")
    facts.should contain("module=example.com/tango-fixtures/greeting/v2@v2.0.0")

    lir = Tango::Dump::LIR.render(snapshot)
    lir.should contain("ExternalCall salute.Greeting")
    lir.should contain("import=example.com/tango-fixtures/greeting/v2")
    lir.should contain("module=example.com/tango-fixtures/greeting/v2@v2.0.0")

    modules = snapshot.go_modules
    modules.size.should eq(1)
    modules.first.path.should eq("example.com/tango-fixtures/greeting/v2")
    modules.first.version.should eq("v2.0.0")
    modules.first.local_path.should eq("spec/fixtures/go_interop/greeting")
  end

  it "emits a direct aliased import and call" do
    go = expect_present(snapshot.go_source)
    go.should contain(%(import salute "example.com/tango-fixtures/greeting/v2"))
    go.should contain(%(fmt.Println(salute.Greeting("Tango"))))
    go.should_not contain("reflect.")
    go.should_not contain("interface{}")
  end

  it "keeps structured hover meaning for the manual Tango declaration" do
    hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, source_path, 3, 15))
    Tango::Compiler::Editor::HoverText.render(hover).should eq("Greeting.call(String) : String")
  end

  it "builds and runs the linked local module" do
    output_path = File.expand_path(File.join(Tango::Workspace::Layout.cache_dir, "go-package-function-#{Process.pid}"))
    error = IO::Memory.new
    result = Tango::Toolchain::Go.build_source(
      expect_present(snapshot.go_source),
      source_path,
      output_path,
      error,
      modules: snapshot.go_modules
    )

    result.status.should eq(0)
    result.diagnostics.should be_empty
    error.to_s.should be_empty

    output = IO::Memory.new
    runtime_error = IO::Memory.new
    status = Process.run(output_path, output: output, error: runtime_error)
    status.success?.should be_true
    runtime_error.to_s.should be_empty
    output.to_s.should eq(File.read("spec/golden/go_package_function.stdout"))
  end
end
