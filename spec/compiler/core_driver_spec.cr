require "../spec_helper"

private def core_driver_nir_nodes(program : Tango::IR::NIR::Program) : Array(Tango::IR::NIR::Stmt)
  pending = Tango::IR::NIR::Walk.children(program).dup
  nodes = [] of Tango::IR::NIR::Stmt
  until pending.empty?
    node = pending.shift
    nodes << node
    pending.concat(Tango::IR::NIR::Walk.children(node))
  end
  nodes
end

describe Tango::Compiler::CoreDriver do
  it "compiles a neutral frontend result without retaining Crystal semantics" do
    source = Tango::Source::CompilationUnit.single(
      Tango::Source::File.new("core_driver.tn", "puts 42\n")
    )
    frontend = Tango::Frontend::Crystal::Driver.run(source)
    snapshot = Tango::Compiler::CoreDriver.run(frontend)

    frontend.ok?.should be_true
    snapshot.ok?.should be_true
    snapshot.nir.should_not be_nil
    snapshot.go_source.should_not be_nil
  end

  it "contains frontend failure data without entering owned phases" do
    source = Tango::Source::CompilationUnit.single(
      Tango::Source::File.new("broken.tn", "if\n")
    )
    frontend = Tango::Frontend::Crystal::Driver.run(source)
    snapshot = Tango::Compiler::CoreDriver.run(frontend)

    frontend.ok?.should be_false
    snapshot.ok?.should be_false
    snapshot.nir.should be_nil
    snapshot.diagnostics.first.code.should eq(Tango::Diagnostics::FRONT_SYNTAX)
  end

  it "owns semantic expansion after the neutral frontend handoff" do
    source = Tango::Source::CompilationUnit.single(
      Tango::Source::File.new("core_expansion.tn", "values = [1, 2]\nputs values[0]\n")
    )
    frontend = Tango::Frontend::Crystal::Driver.run(source)
    frontend_program = expect_present(frontend.program)
    frontend_nodes = core_driver_nir_nodes(frontend_program)

    frontend_nodes.any?(&.is_a?(Tango::IR::NIR::IndexedRead)).should be_false
    frontend_nodes.compact_map(&.as?(Tango::IR::NIR::Call)).any? do |call|
      call.targets.any? do |target|
        target.annotations.any? do |entry|
          entry.path == ["TangoSemantic"] && entry.symbol_args == ["indexed_read"]
        end
      end
    end.should be_true

    snapshot = Tango::Compiler::CoreDriver.run(frontend)
    core_driver_nir_nodes(expect_present(snapshot.nir)).any?(&.is_a?(Tango::IR::NIR::IndexedRead)).should be_true
  end
end
