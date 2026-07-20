require "../spec_helper"
require "../../src/tango/lsp/position"

describe Tango::Lsp::Position::LineIndex do
  it "converts between UTF-16 characters and Tango byte columns" do
    index = Tango::Lsp::Position::LineIndex.new("puts \"😀\"; puts value")

    index.tango_column(0, 16, Tango::Lsp::Position::Encoding::UTF16).should eq(19)
    range = index.range(1, 19, 5, Tango::Lsp::Position::Encoding::UTF16)
    range[:start][:character].should eq(16)
    range[:end][:character].should eq(21)
  end
end
