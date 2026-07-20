require "../../spec_helper"

describe Tango::Frontend::Crystal::Formatting do
  it "delegates canonical layout to Crystal and is idempotent" do
    source = "if true\nputs(  1 )\nend"
    result = Tango::Frontend::Crystal::Formatting.format(source, "sample.tn")

    result.ok?.should be_true
    formatted = expect_present(result.formatted_source)
    formatted.should eq("if true\n  puts(1)\nend\n")
    Tango::Frontend::Crystal::Formatting.format(formatted, "sample.tn").formatted_source.should eq(formatted)
  end

  it "returns a filename-aware syntax diagnostic without formatted output" do
    result = Tango::Frontend::Crystal::Formatting.format("if", "broken.tn")

    result.ok?.should be_false
    result.formatted_source.should be_nil
    diagnostic = result.diagnostics.first
    diagnostic.code.should eq(Tango::Diagnostics::FRONT_SYNTAX)
    diagnostic.file.should eq("broken.tn")
    diagnostic.line.should eq(1)
    diagnostic.column.should eq(3)
  end

  it "contains invalid UTF-8 as formatter check data" do
    source = String.new(Bytes[0xfe_u8, 0xff_u8])
    result = Tango::Frontend::Crystal::Formatting.format(source, "invalid.tn")

    result.ok?.should be_false
    result.formatted_source.should be_nil
    diagnostic = result.diagnostics.first
    diagnostic.code.should eq(Tango::Diagnostics::CHECK_FORMATTER)
    diagnostic.message.should contain("invalid.tn")
    diagnostic.message.should contain("UTF-8")
  end

  it "keeps the valid Tango corpus Crystal-canonical" do
    roots = ["examples", "spec/golden"]
    files = roots.flat_map { |root| Dir.glob(File.join(root, "**", "*.tn")) }.sort

    files.each do |path|
      source = File.read(path)
      result = Tango::Frontend::Crystal::Formatting.format(source, path)
      result.ok?.should be_true
      result.formatted_source.should eq(source), "expected #{path} to be formatter-clean"
    end
  end
end
