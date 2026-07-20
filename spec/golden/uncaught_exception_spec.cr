require "../spec_helper"
require "../../src/tango/dump"

describe "uncaught exception example" do
  source_path = File.join("examples", "uncaught_exception.tn")

  it "commits Crystal-style translation through plans and LIR" do
    source = File.read(source_path)
    snapshot = Tango.snapshot(source, filename: source_path)

    Tango::Dump::NIR.render(snapshot).should contain("Raise")
    Tango::Dump::Plans.render(snapshot).should contain("uncaught_exception CrystalStyle")
    Tango::Dump::LIR.render(snapshot).should contain("UncaughtException CrystalStyle")
  end

  it "prints a Crystal-style header and a Tango source frame" do
    source = File.read(source_path)
    go_source = Tango.compile(source, filename: source_path)
    output = IO::Memory.new
    error = IO::Memory.new

    result = Tango::Toolchain::Go.run_source(go_source, source_path, output, error)

    result.status.should eq(1)
    result.diagnostics.should be_empty
    output.to_s.should be_empty
    error.to_s.should contain("Unhandled exception: boom (Exception)")
    error.to_s.should contain("examples/uncaught_exception.tn:1")
  end

  it "re-panics a foreign top-level panic instead of translating it as Tango" do
    target = Tango::IR::LIR::ExternalTarget.new("go", "regexp", "MustCompile")
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::ExternalCall.new(target, [Tango::IR::LIR::StringConst.new("[")] of Tango::IR::LIR::Value),
    ] of Tango::IR::LIR::Stmt)
    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))
    output = IO::Memory.new
    error = IO::Memory.new

    result = Tango::Toolchain::Go.run_source(source, "foreign_panic.tn", output, error)

    result.status.should eq(1) # `go run` reports the generated process's exit 2 as 1.
    result.diagnostics.should be_empty
    error.to_s.should contain("panic:")
    error.to_s.should_not contain("Unhandled exception")
  end
end
