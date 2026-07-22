require "../../spec_helper"

describe Tango::Target::Go::Source do
  it "deduplicates a default package identifier with an implicit import" do
    requirements = [
      Tango::Target::Go::Runtime::Import.new("fmt", "fmt").as(Tango::Target::Go::Runtime::Requirement),
      Tango::Target::Go::Runtime::Import.new("fmt").as(Tango::Target::Go::Runtime::Requirement),
    ]
    file = Tango::Target::Go::IR::File.new("main", requirements, [] of Tango::Target::Go::IR::Func)

    source = Tango::Target::Go::Source.emit(file)

    source.scan(%(import "fmt")).size.should eq(1)
  end

  it "rejects incompatible identifiers for one import path" do
    requirements = [
      Tango::Target::Go::Runtime::Import.new("example.com/tool/v2", "tool").as(Tango::Target::Go::Runtime::Requirement),
      Tango::Target::Go::Runtime::Import.new("example.com/tool/v2", "other").as(Tango::Target::Go::Runtime::Requirement),
    ]
    file = Tango::Target::Go::IR::File.new("main", requirements, [] of Tango::Target::Go::IR::Func)

    expect_raises(Tango::Target::Go::Source::ImportConflict, /incompatible identifiers/) do
      Tango::Target::Go::Source.emit(file)
    end
  end
end
