require "../spec_helper"

describe Tango::Compiler::Lint do
  it "reports an unread assignment and lowers it as a value-preserving discard" do
    snapshot = Tango.snapshot("stale = 7\nputs 1\n", filename: "unused_local.tn")
    diagnostic = snapshot.diagnostics.find! { |item| item.code == Tango::Diagnostics::LINT_UNUSED_LOCAL }

    diagnostic.origin.lint?.should be_true
    diagnostic.severity.warning?.should be_true
    diagnostic.unnecessary.should be_true
    diagnostic.file.should eq("unused_local.tn")
    diagnostic.line.should eq(1)
    diagnostic.column.should eq(1)
    diagnostic.size.should eq(5)
    diagnostic.message.should eq("unused local variable 'stale' — assigned but never read")
    fix = expect_present(diagnostic.fix)
    fix.kind.prefix_unused_local?.should be_true
    fix.title.should eq("Prefix 'stale' with '_'")
    fix.edits.first.new_text.should eq("_stale")
    snapshot.go_source.to_s.should contain("_ = int32(7)")
    snapshot.go_source.to_s.should_not contain("stale")
  end

  it "uses an underscore prefix as an advisory-lint opt-out while still discarding the Go slot" do
    snapshot = Tango.snapshot("_ignored = 7\nputs 1\n", filename: "ignored_local.tn")

    snapshot.diagnostics.none? { |item| item.code == Tango::Diagnostics::LINT_UNUSED_LOCAL }.should be_true
    snapshot.go_source.to_s.should contain("_ = int32(7)")
    snapshot.go_source.to_s.should_not contain("_ignored")
  end
end
