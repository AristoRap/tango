require "../spec_helper"

describe Tango::Toolchain::Crystal do
  it "raises a typed setup error when Crystal sources cannot be resolved" do
    error = expect_raises(Tango::Toolchain::Crystal::SetupError) do
      Tango::Toolchain::Crystal.setup!("cannot locate Crystal's src directory")
    end

    error.message.should eq("cannot locate Crystal's src directory")
  end
end
