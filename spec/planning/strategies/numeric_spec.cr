require "../../spec_helper"

describe Tango::Planning::Strategies::Numeric do
  it "chooses overflow strategy from analyzed width and signedness" do
    snapshot = Tango.pre_target_snapshot(<<-TN, filename: "numeric_plans.tn")
      x = 1_i8 + 2_i8
      y = 1_i64 + 2_i64
      z = 1_u64 + 2_u64
      TN

    plans = expect_present(snapshot.plans)
    plans.checked_arithmetic.values.map(&.strategy).should eq([
      Tango::IR::CheckedArithmeticStrategy::WideningRoundTrip,
      Tango::IR::CheckedArithmeticStrategy::SignedSameWidth,
      Tango::IR::CheckedArithmeticStrategy::UnsignedSameWidth,
    ])
  end
end
