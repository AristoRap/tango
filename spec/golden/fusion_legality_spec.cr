require "../spec_helper"
require "../../src/tango/dump"

private alias NIR = Tango::IR::NIR
private alias Facts = Tango::Analysis::Facts

private def fusion_operations(node : NIR::Stmt, into : Array(NIR::SemanticCollectionOperation)) : Nil
  if operation = node.as?(NIR::SemanticCollectionOperation)
    into << operation if operation.span.try(&.path.ends_with?("fusion_legality.tn"))
  end
  NIR::Walk.children(node).each { |child| fusion_operations(child, into) }
end

describe "fusion legality facts" do
  source_path = File.join("examples", "fusion_legality.tn")
  snapshot = Tango.snapshot(File.read(source_path), filename: source_path)
  program = expect_present(snapshot.nir)
  facts = expect_present(snapshot.facts)
  operations = [] of NIR::SemanticCollectionOperation
  NIR::Walk.children(program).each { |node| fusion_operations(node, operations) }

  it "records aliased consumers, escape, effects, raises, and bounds" do
    maps = operations.compact_map(&.as?(NIR::CollectionMap))
    mutating = expect_present(maps.find { |map| facts.semantic_collections[map.id].block.captured_mutation })
    map_facts = facts.semantic_collections[mutating.id]

    map_facts.intermediate_escapes.should be_true
    map_facts.block.effects.should eq([Facts::CollectionBlockEffect::CapturedMutation])
    map_facts.block.may_raise.should be_true
    map_facts.block.abrupt_control_flow.should be_false
    map_facts.encounter_order.should eq(Facts::EncounterOrder::Stable)
    map_facts.replayability.should eq(Facts::Replayability::Replayable)
    map_facts.finiteness.should eq(Facts::Finiteness::Finite)
    map_facts.input_cardinality.should eq(Facts::CardinalityBounds.exact(4_i64))
    map_facts.output_cardinality.should eq(Facts::CardinalityBounds.exact(4_i64))

    facts.collection_uses[mutating.id].should contain(
      Facts::CollectionUse.new(
        expect_present(operations.compact_map(&.as?(NIR::CollectionFilter)).find { |filter| facts.semantic_collections[filter.id].block.abrupt_control_flow }).id,
        Facts::CollectionConsumer::Filter,
        Facts::CollectionUsePath::Aliased
      )
    )
  end

  it "distinguishes direct consumers and abrupt flow without inventing effects" do
    filters = operations.compact_map(&.as?(NIR::CollectionFilter))
    abrupt = expect_present(filters.find { |filter| facts.semantic_collections[filter.id].block.abrupt_control_flow })
    abrupt_facts = facts.semantic_collections[abrupt.id]
    abrupt_facts.block.effects.should be_empty
    abrupt_facts.block.may_raise.should be_false
    abrupt_facts.output_cardinality.should eq(Facts::CardinalityBounds.new(0_i64, nil))

    direct_map = expect_present(operations.compact_map(&.as?(NIR::CollectionMap)).find do |map|
      facts.collection_uses[map.id]?.try(&.any?(&.path.direct?)) || false
    end)
    direct_use = expect_present(facts.collection_uses[direct_map.id].find(&.path.direct?))
    direct_use.kind.should eq(Facts::CollectionConsumer::Filter)
    facts.semantic_collections[direct_map.id].intermediate_escapes.should be_false
    direct_filter = facts.semantic_collections[direct_use.consumer]
    direct_filter.output_cardinality.should eq(Facts::CardinalityBounds.new(0_i64, 4_i64))
  end

  it "keeps both compilation profiles on the eager fallback" do
    development = expect_present(snapshot.plans)
    release = Tango::Planning::Driver.run(program, facts, Tango::Compiler::CompilationProfile::Release)

    operations.each do |operation|
      development.semantic_collections[operation.id].should be_a(Tango::Planning::Plans::MaterializeViaFallback)
      release.semantic_collections[operation.id].should be_a(Tango::Planning::Plans::MaterializeViaFallback)
    end

    dump = Tango::Dump::Facts.render(snapshot)
    dump.should contain("semantic_collection_facts escapes=true effects=[CapturedMutation]")
    dump.should contain("collection_use Filter")
    dump.should contain("path=Direct")
    dump.should contain("path=Aliased")
    dump.should contain("order=Stable replay=Replayable finiteness=Finite input=4 output=4")
  end
end
