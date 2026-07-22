require "../spec_helper"

describe Tango::Analysis::Facts::GoExternal do
  it "parses a package-function binding into package + name" do
    external = Tango::Analysis::Facts::GoExternal.parse("strings.ToUpper")
    external.import_path.should eq("strings")
    external.package_identifier.should eq("strings")
    external.name.should eq("ToUpper")
    external.receiver_method?.should be_false
    external.to_s.should eq("strings.ToUpper")
  end

  it "parses a bare function binding with no package" do
    external = Tango::Analysis::Facts::GoExternal.parse("panic")
    external.import_path.should be_nil
    external.package_identifier.should be_nil
    external.name.should eq("panic")
    external.receiver_method?.should be_false
  end

  it "parses a leading-dot binding as the receiver-method form" do
    external = Tango::Analysis::Facts::GoExternal.parse(".Lock")
    external.receiver_method?.should be_true
    external.name.should eq("Lock")
    external.import_path.should be_nil
    external.package_identifier.should be_nil
    external.to_s.should eq(".Lock")
  end

  it "keeps a module import path separate from its package identifier" do
    dependency = Tango::IR::ExternalDependency.new("example.com/tool/v2", "v2.0.0")
    external = Tango::Analysis::Facts::GoExternal.package("example.com/tool/v2", "tool", "Open", dependency)

    external.import_path.should eq("example.com/tool/v2")
    external.package_identifier.should eq("tool")
    external.name.should eq("Open")
    external.dependency.should eq(dependency)
    external.to_s.should eq("tool.Open")
  end
end
