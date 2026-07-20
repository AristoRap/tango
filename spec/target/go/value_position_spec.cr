require "../../spec_helper"

describe "Go target value-position lowering" do
  it "emits a nested IfValue as a typed expression" do
    source = Tango.compile("flag = true\nputs(flag && 1 < 2)\n")

    source.should contain("fmt.Println(func() bool {")
    source.should contain("if flag {")
    source.should contain("return int32(1) < int32(2)")
    source.should_not contain("unsupported LIR value")
  end

  it "emits a discarded IfValue as a statement while preserving both arms" do
    value = Tango::IR::LIR::IfValue.new(
      Tango::IR::LIR::Temp.new("flag"),
      Tango::IR::LIR::Temp.new("left"),
      Tango::IR::LIR::Temp.new("right"),
      Tango::IR::Type.bool
    )
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Discard.new(value),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("if flag {")
    source.should contain("_ = left")
    source.should contain("_ = right")
    source.should_not contain("unsupported LIR value")
  end
end
