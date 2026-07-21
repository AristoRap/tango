require "./spec_helper"

# Cross-cutting ratchets for the architecture audit. Behavioral failures live
# beside their owning subsystem; this file prevents the same divergent shapes
# from being reintroduced under a different feature name.
module ArchitectureRegressions
  ROOT = File.expand_path("..", __DIR__)

  LARGE_FILE_DEBT = {} of String => Int32

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

  it "derives disk root ownership only from explicit manifest entrypoints" do
    workspace = ArchitectureRegressions.read("src/tango/lsp/workspace.cr")
    ownership = ArchitectureRegressions.read("src/tango/lsp/root_ownership_index.cr")
    workspace.should_not match(/source\.files\.size\s*>/)
    workspace.should_not contain(".max_by?")
    workspace.should_not match(/rescue\s*\n\s*next/)
    ownership.should_not contain("Dir.glob")
    ownership.should contain(%(MANIFEST_NAME = "tango.json"))
    ownership.should contain("manifest_entrypoints(root)")
    ownership.should contain("candidates.size == 1")
  end

  it "keeps Array stage-interleaving fusion disabled" do
    strategy = ArchitectureRegressions.read("src/tango/planning/strategies/semantic_collections.cr")
    strategy.should_not contain("IR::NIR::CollectionFold")
    strategy.should_not contain("FusedCollectionTransform.new")
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
    call_metadata = ArchitectureRegressions.read("src/tango/frontend/crystal/call_metadata.cr")

    select_source.should contain("select_index_condition?")
    select_source.should contain("select_bug_sentinel?")
    select_source.should contain("valid_select_action_arity?")
    call_metadata.should contain(%(when "tango_chan_close"))
    call_metadata.should contain("unknown channel primitive")
  end

  it "keeps editor diagnostic transport aligned with the shared diagnostic" do
    diagnostic = ArchitectureRegressions.getters(
      ArchitectureRegressions.read("src/tango/diagnostics/diagnostic.cr"),
      "Diagnostic"
    )
    transported = ArchitectureRegressions.getters(
      ArchitectureRegressions.read("src/tango/transport/diagnostic_data.cr"),
      "DiagnosticData"
    )

    transported.should eq(diagnostic)
    server = ArchitectureRegressions.read("src/tango/lsp/server_diagnostics.cr")
    server.should contain("d.related.map")
    server.should contain("d.hints.map")
    server.should contain("diagnostic.range")
  end

  it "uses one strict transport authority for shared worker and bundle values" do
    codec = ArchitectureRegressions.read("src/tango/lsp/analysis_codec.cr")
    bundle = ArchitectureRegressions.read("src/tango/frontend/bundle/codec/document.cr")
    shared = %w(value_data source_data syntax_data diagnostic_data).map do |name|
      ArchitectureRegressions.read("src/tango/transport/#{name}.cr")
    end.join("\n")

    %w(
      RangeData
      TypeData
      SurfaceParameterData
      SurfaceDeclarationData
      SurfaceScopeData
      DiagnosticData
      FileData
      RequireData
      EdgeData
    ).each do |name|
      codec.should contain("alias #{name} = Transport::#{name}")
      codec.should_not match(/class #{name}\b/)
    end
    bundle.should contain("Transport::SurfaceData")
    bundle.should contain("Transport::DiagnosticData")
    bundle.should contain("Transport::FileData")
    shared.scan("include JSON::Serializable::Strict").size.should eq(13)
  end

  it "derives strict NIR fields from decoder consumption" do
    decoder = ArchitectureRegressions.read("src/tango/frontend/bundle/codec/nir_decoder.cr")
    decoder.should contain("reject_unconsumed")
    decoder.should_not contain("expected_fields")
    decoder.should_not contain("STMT_FIELDS")
    decoder.should_not contain("EXPR_FIELDS")
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

  it "admits no responsibility-heavy source file at 700 lines or more" do
    large = Dir.glob(File.join(ArchitectureRegressions::ROOT, "src/**/*.cr")).compact_map do |path|
      relative = path.lchop("#{ArchitectureRegressions::ROOT}/")
      count = File.read(path).lines.size
      {relative, count} if count >= 700
    end.to_h

    unclassified = large.keys - ArchitectureRegressions::LARGE_FILE_DEBT.keys
    unclassified.should be_empty, "new responsibility-heavy files: #{unclassified.join(", ")}"
    large.should be_empty
    ArchitectureRegressions::LARGE_FILE_DEBT.each do |path, ceiling|
      ArchitectureRegressions.lines(path).should be <= ceiling, "#{path} grew beyond its ratchet"
    end
  end

  it "keeps each extracted large-file responsibility behind its subsystem barrel" do
    {
      "src/tango/ir/lir.cr"           => %w(./lir/collection_value ./lir/concurrency_value),
      "src/tango/frontend/crystal.cr" => %w(./crystal/call_metadata),
      "src/tango/compiler/editor.cr"  => %w(./editor/index_symbol_families),
      "src/tango/lowering.cr"         => %w(./lowering/declaration_lowering),
      "src/tango/lsp.cr"              => %w(./lsp/server_mutations),
    }.each do |barrel, responsibilities|
      source = ArchitectureRegressions.read(barrel)
      responsibilities.each { |path| source.should contain(%(require "#{path}")) }
    end
  end
end
