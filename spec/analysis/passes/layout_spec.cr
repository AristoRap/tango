require "../../spec_helper"

describe Tango::Analysis::Passes::Layout do
  it "records concrete-first exception ancestry as a fact" do
    snapshot = Tango.snapshot(<<-TN, filename: "exception_layout.tn")
      class BaseError < Exception
      end
      class SubError < BaseError
      end
      TN

    facts = expect_present(snapshot.facts)
    facts.exception_hierarchies["BaseError"].ancestors.should eq(["BaseError", "Exception"])
    facts.exception_hierarchies["SubError"].ancestors.should eq(["SubError", "BaseError", "Exception"])
  end
end
