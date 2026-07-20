require "../../spec_helper"

describe Tango::Frontend::Crystal::DiagnosticMessage do
  it "removes Crystal's root qualifier from free function names" do
    message = "method ::maybe must return (Int32 | Nil) but it is returning String"

    Tango::Frontend::Crystal::DiagnosticMessage.render(message).should eq("method maybe must return (Int32 | Nil) but it is returning String")
  end

  it "preserves namespace qualifiers" do
    Tango::Frontend::Crystal::DiagnosticMessage.render("method Thing::make failed").should eq("method Thing::make failed")
  end
end
