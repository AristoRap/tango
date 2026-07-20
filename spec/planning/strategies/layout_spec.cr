require "../../spec_helper"

describe Tango::Planning::Strategies::Layout do
  it "plans exception runtime support from the analyzed hierarchy" do
    snapshot = Tango.snapshot(<<-TN, filename: "exception_plan.tn")
      class BaseError < Exception
      end
      class SubError < BaseError
      end
      TN

    plan = expect_present(snapshot.plans).layouts["SubError"]
    plan.exception_runtime?.should be_true
    plan.exception_ancestors.should eq(["SubError", "BaseError", "Exception"])
  end
end
