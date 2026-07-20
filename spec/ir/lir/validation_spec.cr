require "../../spec_helper"

private alias LIR = Tango::IR::LIR

describe "LIR validation" do
  it "finds unsupported nodes nested in select operands and bodies" do
    channel_loc = LIR::SourceLoc.new("select.tn", 2, 8)
    body_loc = LIR::SourceLoc.new("select.tn", 3, 5)
    channel = LIR::UnsupportedValue.new("unsupported channel", channel_loc)
    body = LIR::UnsupportedStmt.new("unsupported arm body", body_loc)
    arm = LIR::Select::Arm.new(
      LIR::Select::Arm::Kind::Receive,
      channel,
      nil,
      nil,
      Tango::IR::Type.int(:i32),
      [body] of LIR::Stmt
    )
    program = LIR::Program.new([LIR::Select.new([arm])] of LIR::Stmt)

    LIR.unsupported_reasons(program).should eq([
      LIR::UnsupportedReason.new("unsupported channel", channel_loc),
      LIR::UnsupportedReason.new("unsupported arm body", body_loc),
    ])
  end
end
