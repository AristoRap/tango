require "../../spec_helper"

describe Tango::Analysis::Passes::UnionFlows do
  it "records a strict source-union subset flowing into an if result union" do
    snapshot = Tango.snapshot(<<-TN, filename: "union_widen.tn")
      def choose(number : Bool) : Int32 | String
        if number
          7
        else
          "seven"
        end
      end

      def widen(number : Bool, absent : Bool) : Int32 | String | Nil
        if absent
          nil
        else
          choose(number)
        end
      end

      value = widen(true, false)
      TN

    flows = expect_present(snapshot.facts).union_flows.values
    flows.size.should eq(1)
    flows.first.source.to_s.should eq("Int32 | String")
    flows.first.target.to_s.should eq("Int32 | String | Nil")
  end
end
