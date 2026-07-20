require "../spec_helper"

describe Tango::Diagnostics::Renderer do
  it "renders a source range with related locations and hints" do
    source = "first\nvalue = nope\nlast"
    diagnostic = Tango::Diagnostic.new(
      Tango::Diagnostic::Origin::Emit,
      Tango::Diagnostic::Severity::Error,
      "emit.example",
      "unknown value",
      file: "example.tn",
      range: Tango::Source::Range.new("example.tn", 14, 18),
      related: [{Tango::Source::Range.new("example.tn", 0, 5), "declared here"}],
      hints: ["use a defined value"]
    )

    rendered = Tango::Diagnostics::Renderer.render(source, diagnostic, path: "example.tn")

    rendered.should eq(<<-TEXT)
    error: unknown value
     --> example.tn:2:9
      |
    2 | value = nope
      |         ^^^^
      = note: declared here (example.tn:1:1)
      = help: use a defined value
    TEXT
  end

  it "converts byte offsets to character columns and clamps the underline" do
    source = "é = wrong\n"
    diagnostic = Tango::Diagnostic.new(
      Tango::Diagnostic::Origin::Frontend,
      Tango::Diagnostic::Severity::Warning,
      "front.example",
      "check this",
      file: "unicode.tn",
      range: Tango::Source::Range.new("unicode.tn", 5, 100)
    )

    rendered = Tango::Diagnostics::Renderer.render(source, diagnostic, path: "unicode.tn")

    rendered.should contain("warning: check this")
    rendered.should contain("--> unicode.tn:1:5")
    rendered.should contain("|     ^^^^^")
  end

  it "uses line and byte-column fields when no exact range is available" do
    source = "one\n\tbad"
    diagnostic = Tango::Diagnostic.new(
      Tango::Diagnostic::Origin::Frontend,
      Tango::Diagnostic::Severity::Error,
      "front.example",
      "bad token",
      line: 2,
      column: 2,
      size: 3
    )

    rendered = Tango::Diagnostics::Renderer.render(source, diagnostic)

    rendered.should contain("--> <source>:2:2")
    rendered.should contain("| \t^^^")
  end

  it "adds ANSI styling only when requested" do
    diagnostic = Tango::Diagnostic.new(
      Tango::Diagnostic::Origin::Emit,
      Tango::Diagnostic::Severity::Error,
      "emit.example",
      "broken"
    )

    plain = Tango::Diagnostics::Renderer.render("x", diagnostic)
    colored = Tango::Diagnostics::Renderer.render("x", diagnostic, color: true)

    plain.should_not contain("\e[")
    colored.should contain("\e[1;31merror\e[0m")
  end
end

describe Tango::Diagnostic do
  it "renders a source-free check through the shared CLI diagnostic spelling" do
    diagnostic = Tango::Diagnostic.new(
      Tango::Diagnostic::Origin::Check,
      Tango::Diagnostic::Severity::Error,
      Tango::Diagnostics::CHECK_GO,
      "no Go toolchain found"
    )

    diagnostic.to_s.should eq("tango: no Go toolchain found")
  end
end
