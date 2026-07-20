require "../../spec_helper"

describe Tango::Frontend::Crystal::InternalCheck do
  it "rejects user application of the reserved semantic annotation" do
    source = <<-TN
      @[TangoSemantic(:map)]
      def counterfeit(& : Int32 -> Int32) : Array(Int32)
        Array(Int32).new
      end
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: "reserved_semantic_annotation.tn")
    diagnostic = snapshot.diagnostics.find!(&.code.==(Tango::Diagnostics::INTERNAL_RESERVED))

    diagnostic.message.should contain("reserved prelude-only semantic annotation")
    diagnostic.line.should eq(1)
    diagnostic.column.should eq(3)
  end

  it "enforces the annotation boundary in required source files" do
    dependency = Tango::Source::File.new(
      "dependency.tn",
      "class Counterfeit\n  @[TangoSemantic(:map)]\n  def value : Int32\n    1\n  end\nend\n",
      "dependency"
    )
    resolver = Tango::Frontend::SourceGraph::Resolver.new do |request, _from|
      request == "./dependency" ? [dependency] : [] of Tango::Source::File
    end

    snapshot = Tango.pre_target_snapshot(
      "require \"./dependency\"\nputs Counterfeit.new.value\n",
      filename: "main.tn",
      resolver: resolver
    )
    diagnostic = snapshot.diagnostics.find!(&.code.==(Tango::Diagnostics::INTERNAL_RESERVED))

    diagnostic.file.should eq("dependency.tn")
    diagnostic.line.should eq(2)
    diagnostic.column.should eq(5)
  end
end
