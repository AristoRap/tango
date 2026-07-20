require "../../spec_helper"

describe Tango::Target::Go::FromLIR do
  it "mechanically spells report comparison, conversion, and rounding" do
    i32 = Tango::IR::Type.int(:i32)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new(
        "comparison",
        Tango::IR::LIR::StringCompare.new(Tango::IR::LIR::StringConst.new("Berlin"), Tango::IR::LIR::StringConst.new("Amsterdam")),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
      Tango::IR::LIR::Assign.new(
        "count",
        Tango::IR::LIR::NumericConvert.new(Tango::IR::LIR::IntConst.new("3"), i32, Tango::IR::Type.float64),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
      Tango::IR::LIR::Assign.new(
        "rounded",
        Tango::IR::LIR::FloatIntrinsic.new(
          Tango::IR::LIR::FloatIntrinsicOperation::RoundEven,
          Tango::IR::LIR::FloatConst.new("11.5"),
          Tango::IR::Type.float64
        ),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain(%(comparison := tangoStringCompare("Berlin", "Amsterdam")))
    source.should contain("return int32(strings.Compare(left, right))")
    source.should contain("count := float64(int32(3))")
    source.should contain("rounded := tangoRoundEvenF64(float64(11.5))")
    source.should contain("return math.RoundToEven(value)")
  end
end
