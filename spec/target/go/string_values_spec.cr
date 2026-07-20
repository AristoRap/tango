require "../../spec_helper"

describe Tango::Target::Go::FromLIR do
  it "spells committed integer-system operations through typed helpers" do
    i8 = Tango::IR::Type.int(:i8)
    u16 = Tango::IR::Type.int(:u16)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new("wrapped", Tango::IR::LIR::IntegerOperationValue.new(Tango::IR::LIR::IntegerOperation::WrappingAdd, Tango::IR::LIR::IntConst.new("127", i8), Tango::IR::LIR::IntConst.new("1", i8), i8), Tango::IR::LIR::Assign::Mode::Declare),
      Tango::IR::LIR::Assign.new("shifted", Tango::IR::LIR::IntegerOperationValue.new(Tango::IR::LIR::IntegerOperation::ShiftLeft, Tango::IR::LIR::IntConst.new("1", u16), Tango::IR::LIR::IntConst.new("2"), u16), Tango::IR::LIR::Assign::Mode::Declare),
      Tango::IR::LIR::Assign.new("parsed", Tango::IR::LIR::StringToInteger.new(Tango::IR::LIR::StringConst.new("ff"), [Tango::IR::LIR::IntConst.new("16"), Tango::IR::LIR::BoolConst.new(true), Tango::IR::LIR::BoolConst.new(false), Tango::IR::LIR::BoolConst.new(false), Tango::IR::LIR::BoolConst.new(true), Tango::IR::LIR::BoolConst.new(false)] of Tango::IR::LIR::Value, u16), Tango::IR::LIR::Assign::Mode::Declare),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))
    source.should contain("wrapped := tangoWrappingAddI8(int8(127), int8(1))")
    source.should contain("shifted := tangoShiftLeftU16(uint16(1), int32(2))")
    source.should contain(%(parsed := tangoStringToU16("ff", int32(16), true, false, false, true, false)))
  end

  it "materializes a planned whitespace split into Array(String)" do
    string = Tango::IR::Type.string
    array = Tango::IR::Type.array(string)
    program = Tango::IR::LIR::Program.new(
      [
        Tango::IR::LIR::Assign.new(
          "words",
          Tango::IR::LIR::MaterializedStringSplit.new(Tango::IR::LIR::StringConst.new("a b"), array),
          Tango::IR::LIR::Assign::Mode::Declare
        ),
      ] of Tango::IR::LIR::Stmt,
      arrays: [Tango::IR::LIR::ArrayType.new(array, string, true)]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain(%(words := tangoStringSplit("a b")))
    source.should contain("fields := strings.Fields(s)")
    source.should contain("return &fields")
  end

  it "spells exact separator splitting and typed decimal parsing through runtime helpers" do
    string = Tango::IR::Type.string
    array = Tango::IR::Type.array(string)
    program = Tango::IR::LIR::Program.new(
      [
        Tango::IR::LIR::Assign.new(
          "fields",
          Tango::IR::LIR::MaterializedStringSplit.new(Tango::IR::LIR::StringConst.new("a;;b"), array, Tango::IR::LIR::StringConst.new(";")),
          Tango::IR::LIR::Assign::Mode::Declare
        ),
        Tango::IR::LIR::Assign.new(
          "measurement",
          Tango::IR::LIR::StringToFloat.new(Tango::IR::LIR::StringConst.new("12.5")),
          Tango::IR::LIR::Assign::Mode::Declare
        ),
      ] of Tango::IR::LIR::Stmt,
      arrays: [Tango::IR::LIR::ArrayType.new(array, string, true)]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain(%(fields := tangoStringSplitOn("a;;b", ";")))
    source.should contain("func tangoStringSplitOn(s string, separator string) *[]string")
    source.should contain("measurement := tangoStringToF64(\"12.5\")")
    source.should contain("func tangoStringToF64(s string) float64")
    source.should contain("Invalid Float64: ")
    source.should contain("tangoArgumentError")
  end

  it "spells character operations with typed Unicode helpers" do
    string = Tango::IR::LIR::StringConst.new("Aé")
    block = Tango::IR::LIR::Closure.new(
      [Tango::IR::LIR::Param.new("char", Tango::IR::Type.char)],
      Tango::IR::Type.bool,
      [Tango::IR::LIR::AbruptExit.new(Tango::IR::LIR::AbruptExit::Shape::Return, Tango::IR::LIR::BoolConst.new(true))] of Tango::IR::LIR::Stmt
    )
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new("size", Tango::IR::LIR::CollectionCount.new(Tango::IR::LIR::StringCodepoints.new(string)), Tango::IR::LIR::Assign::Mode::Declare),
      Tango::IR::LIR::Assign.new("char", Tango::IR::LIR::StringCharAt.new(string, Tango::IR::LIR::IntConst.new("1")), Tango::IR::LIR::Assign::Mode::Declare),
      Tango::IR::LIR::StringEachChar.new(string, block),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("size := tangoStringSize(\"Aé\")")
    source.should contain("char := tangoStringCharAt(\"Aé\", int32(1))")
    source.should contain("func tangoStringSize(s string) int32")
    source.should contain("func tangoStringCharAt(s string, index int32) rune")
    source.should contain("tangoStringEachCharBreak(\"Aé\", func(char rune) bool")
  end
end
