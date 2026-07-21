require "./spec_helper"

# Cross-cutting ratchets for the architecture audit. Behavioral failures live
# beside their owning subsystem; this file prevents the same divergent shapes
# from being reintroduced under a different feature name.
module ArchitectureRegressions
  ROOT = File.expand_path("..", __DIR__)

  LARGE_FILE_DEBT = {
    "src/tango/ir/lir/value.cr"            => 797,
    "src/tango/frontend/crystal/to_nir.cr" => 796,
    "src/tango/compiler/editor/index.cr"   => 785,
    "src/tango/lowering/to_lir.cr"         => 734,
    "src/tango/lsp/server.cr"              => 733,
    "src/tango/lsp/analysis_codec.cr"      => 725,
  }

  def self.read(path : String) : String
    File.read(File.join(ROOT, path))
  end

  def self.lines(path : String) : Int32
    read(path).lines.size
  end

  def self.getters(source : String, class_name : String) : Array(String)
    body = source.split(/(?:class|struct) #{class_name}\b/, 2)[1].split(/\n\s+def initialize/, 2)[0]
    body.scan(/^\s+getter\??\s+(\w+)/m).map(&.[1]).uniq.sort
  end
end

describe "architecture audit regressions" do
  it "keeps semantic compiler walks inside the isolated editor worker" do
    files = Dir.glob(File.join(ArchitectureRegressions::ROOT, "src/tango/lsp/**/*.cr")).sort
    owners = files.select { |path| File.read(path).includes?("Tango.pre_target_snapshot") }
      .map { |path| path.lchop("#{ArchitectureRegressions::ROOT}/") }

    owners.should eq(["src/tango/lsp/analysis_worker.cr"])
    ArchitectureRegressions.read("src/tango/lsp/document.cr").should contain("Tango.editor_surface_snapshot")
  end

  it "does not infer editor root ownership from graph size" do
    workspace = ArchitectureRegressions.read("src/tango/lsp/workspace.cr")
    workspace.should_not match(/source\.files\.size\s*>/)
    workspace.should_not contain(".max_by?")
    workspace.should_not match(/rescue\s*\n\s*next/)
    broad_scans = workspace.lines.count { |line| line.includes?("Dir.glob(File.join(root") }
    broad_scans.should eq(2), <<-MESSAGE
    One scan catalogs bundled packages; the other remaining broad disk-root
    discovery is tracked debt. Do not add another scan; replace ownership
    discovery with an explicit cached reverse index.
    MESSAGE
  end

  it "keeps unsupported target values fail-loud" do
    values = ArchitectureRegressions.read("src/tango/target/go/from_lir/values.cr")
    values.should contain(%(raise ArgumentError.new("unsupported LIR value: \#{value.reason}")))
    values.should contain(%(raise ArgumentError.new("unsupported LIR value: \#{value.class.name}")))
    values.should_not contain("IR::StringLit.new(value.reason)")
    values.should_not contain(%(IR::StringLit.new("unsupported LIR value")))
  end

  it "pins complete select reconstruction and channel primitive dispatch" do
    select_source = ArchitectureRegressions.read("src/tango/frontend/crystal/select_translation.cr")
    to_nir = ArchitectureRegressions.read("src/tango/frontend/crystal/to_nir.cr")

    select_source.should contain("select_index_condition?")
    select_source.should contain("select_bug_sentinel?")
    select_source.should contain("valid_select_action_arity?")
    to_nir.should contain(%(when "tango_chan_close"))
    to_nir.should contain("unknown channel primitive")
  end

  it "keeps editor diagnostic transport aligned with the shared diagnostic" do
    diagnostic = ArchitectureRegressions.getters(
      ArchitectureRegressions.read("src/tango/diagnostics/diagnostic.cr"),
      "Diagnostic"
    )
    transported = ArchitectureRegressions.getters(
      ArchitectureRegressions.read("src/tango/lsp/analysis_codec.cr"),
      "DiagnosticData"
    )

    transported.should eq(diagnostic)
    server = ArchitectureRegressions.read("src/tango/lsp/server_diagnostics.cr")
    server.should contain("d.related.map")
    server.should contain("d.hints.map")
    server.should contain("diagnostic.range")
  end

  it "uses one canonical path-identity implementation" do
    %w(
      src/tango/frontend/source_graph.cr
      src/tango/lsp/workspace.cr
      src/tango/cli/format.cr
      src/tango/workspace/layout.cr
    ).each do |path|
      source = ArchitectureRegressions.read(path)
      source.should contain("Source::File.canonical_identity"), path
      source.should_not contain("File.realpath"), path
    end
  end

  it "shares the parser-owned surface roots with internal checks" do
    driver = ArchitectureRegressions.read("src/tango/frontend/crystal/driver.cr")
    surface = ArchitectureRegressions.read("src/tango/frontend/crystal/syntax_surface_builder.cr")

    driver.should contain("SyntaxSurfaceBuilder.build_with_roots")
    driver.should_not contain("Semantic.parse")
    surface.should contain("roots[file.identity] = root")
  end

  it "ratchets large ownership files downward and admits no new one" do
    large = Dir.glob(File.join(ArchitectureRegressions::ROOT, "src/**/*.cr")).compact_map do |path|
      relative = path.lchop("#{ArchitectureRegressions::ROOT}/")
      count = File.read(path).lines.size
      {relative, count} if count >= 700
    end.to_h

    unclassified = large.keys - ArchitectureRegressions::LARGE_FILE_DEBT.keys
    unclassified.should be_empty, "new responsibility-heavy files: #{unclassified.join(", ")}"
    ArchitectureRegressions::LARGE_FILE_DEBT.each do |path, ceiling|
      ArchitectureRegressions.lines(path).should be <= ceiling, "#{path} grew beyond its ratchet"
    end
  end
end
