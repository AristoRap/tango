require "../spec_helper"

describe Tango::IR::Type do
  it "owns language sentinel identity" do
    Tango::IR::Type.klass("Exception").exception_root?.should be_true
    Tango::IR::Type.klass("OtherError").exception_root?.should be_false
    Tango::IR::Type.klass("NoReturn").no_return?.should be_true
    Tango::IR::Type.unknown.no_return?.should be_false
  end

  it "renders nilable unions explicitly for user-facing source presentation" do
    type = Tango::IR::Type.array(Tango::IR::Type.int(:i32).with_nil)

    type.to_s.should eq("Array(Int32?)")
    type.to_semantic_s.should eq("Array((Int32 | Nil))")
  end
end
