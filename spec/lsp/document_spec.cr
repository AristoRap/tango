require "../spec_helper"
require "../../src/tango/lsp"

describe Tango::Lsp::Document do
  it "owns one checked snapshot per document version" do
    document = Tango::Lsp::Document.new("file:///doc.tn", "/doc.tn", "x = 1\nputs x", 1)
    first = document.snapshot

    document.snapshot.same?(first).should be_true
    document.semantic_snapshot.should be_nil
    first.target_ir.should be_nil
    first.go_source.should be_nil

    document.update("x = 2\nputs x", 2)
    document.version.should eq(2)
    document.snapshot.same?(first).should be_false
  end
end
