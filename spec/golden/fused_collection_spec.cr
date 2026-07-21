require "../spec_helper"
require "../../src/tango/dump"

private alias FusedNIR = Tango::IR::NIR

private def find_fused_fold(program : FusedNIR::Program) : FusedNIR::CollectionFold?
  program.body.each do |node|
    find_fused_fold(node).try { |fold| return fold }
  end
  nil
end

private def find_fused_fold(node : FusedNIR::Stmt) : FusedNIR::CollectionFold?
  if fold = node.as?(FusedNIR::CollectionFold)
    return fold if fold.span.try(&.path.ends_with?("fused_collection.tn"))
  end
  FusedNIR::Walk.children(node).each do |child|
    find_fused_fold(child).try { |fold| return fold }
  end
  nil
end

describe "collection fusion safety" do
  source_path = File.join("examples", "fused_collection.tn")
  source = File.read(source_path)
  development = Tango.snapshot(source, filename: source_path)
  release = Tango.snapshot(source, filename: source_path, profile: Tango::Compiler::CompilationProfile::Release)
  program = expect_present(release.nir)
  fold = expect_present(find_fused_fold(program))

  it "keeps Array select/map/fold eager in every profile" do
    development.diagnostics.should eq(release.diagnostics)
    Tango::Dump::NIR.render(development).should eq(Tango::Dump::NIR.render(release))
    Tango::Dump::Facts.render(development).should eq(Tango::Dump::Facts.render(release))

    development_plan = expect_present(development.plans).semantic_collections[fold.id]
    development_plan.should be_a(Tango::Planning::Plans::MaterializeViaFallback)

    release_plan = expect_present(release.plans).semantic_collections[fold.id]
    release_plan.should be_a(Tango::Planning::Plans::MaterializeViaFallback)
  end

  it "does not commit an Array fused traversal into LIR or Go" do
    plans = Tango::Dump::Plans.render(release)
    plans.should_not contain("semantic_collection FusedCollectionTraversal Int32")

    lir = Tango::Dump::LIR.render(release)
    lir.should_not contain("FusedCollectionTraversal Int32 Source=ArrayElements(Int32)")

    go = expect_present(release.go_source)
    go.should contain("tangoArrayNew")
    go.should contain("tangoArrayPush")
  end

  it "retains the fallback when a transform can raise" do
    unsafe_sources = {
      "integer_arithmetic" => <<-TANGO,
        values = [1, 2, 3]
        puts values.select { |value| 10 // value > 2 }.map { |value| value }.reduce(0) { |sum, value| sum + value }
        TANGO
      "float_parse" => <<-TANGO,
        values = ["1.5", "bad"]
        puts values.select { |value| value.to_f > 0.0 }.map { |value| value }.reduce("") { |sum, value| sum + value }
        TANGO
      "checked_cast" => <<-TANGO,
        values = ["one", 2]
        puts values.select { |value| value.as(String).size > 0 }.map { |value| value }.reduce("") { |sum, value| sum + value.as(String) }
        TANGO
      "exception_order" => <<-TANGO,
        values = ["1.5", "bad", 1]
        puts values.select { |value| value.as(String).to_f > 0.0 }.map { |value| value.as(Int32) }.reduce(0) { |sum, value| sum + value }
        TANGO
    }

    unsafe_sources.each do |name, unsafe|
      path = "unsafe_fusion_#{name}.tn"
      snapshot = Tango.snapshot(unsafe, filename: path, profile: Tango::Compiler::CompilationProfile::Release)
      unsafe_program = expect_present(snapshot.nir)
      unsafe_fold = expect_present(find_fused_fold_for_path(unsafe_program, path))
      expect_present(snapshot.plans).semantic_collections[unsafe_fold.id].should be_a(Tango::Planning::Plans::MaterializeViaFallback)
    end
  end
end

private def find_fused_fold_for_path(node : FusedNIR::Stmt, path : String) : FusedNIR::CollectionFold?
  if fold = node.as?(FusedNIR::CollectionFold)
    return fold if fold.span.try(&.path.ends_with?(path))
  end
  FusedNIR::Walk.children(node).each do |child|
    find_fused_fold_for_path(child, path).try { |fold| return fold }
  end
  nil
end

private def find_fused_fold_for_path(program : FusedNIR::Program, path : String) : FusedNIR::CollectionFold?
  program.body.each do |node|
    find_fused_fold_for_path(node, path).try { |fold| return fold }
  end
  nil
end
