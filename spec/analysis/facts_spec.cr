require "../spec_helper"

describe Tango::Analysis::Facts::GoExternal do
  it "parses a package-function binding into package + name" do
    external = Tango::Analysis::Facts::GoExternal.parse("strings.ToUpper")
    external.package_name.should eq("strings")
    external.name.should eq("ToUpper")
    external.receiver_method?.should be_false
    external.to_s.should eq("strings.ToUpper")
  end

  it "parses a bare function binding with no package" do
    external = Tango::Analysis::Facts::GoExternal.parse("panic")
    external.package_name.should be_nil
    external.name.should eq("panic")
    external.receiver_method?.should be_false
  end

  it "parses a leading-dot binding as the receiver-method form" do
    external = Tango::Analysis::Facts::GoExternal.parse(".Lock")
    external.receiver_method?.should be_true
    external.name.should eq("Lock")
    external.package_name.should be_nil
    external.to_s.should eq(".Lock")
  end
end
