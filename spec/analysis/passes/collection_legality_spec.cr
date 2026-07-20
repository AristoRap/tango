require "../../spec_helper"

private alias NIR = Tango::IR::NIR
private alias Facts = Tango::Analysis::Facts

describe Tango::Analysis::Passes::CollectionLegality do
  it "does not infer source laws from Enumerable conformance alone" do
    custom = Tango::IR::Type.klass("Bag")
    source = NIR::Local.new(Tango::NodeId.new("source"), "bag", custom, nil)
    body = NIR::Block.new(Tango::NodeId.new("body"), [] of NIR::Stmt, nil)
    signature = Tango::IR::ProcSignature.new([Tango::IR::Type.int(:i32)], Tango::IR::Type.int(:i32))
    block = NIR::BlockLiteral.new(Tango::NodeId.new("block"), [] of NIR::BlockArg, body, signature, signature.to_type, nil)
    array = Tango::IR::Type.array(Tango::IR::Type.int(:i32))
    fallback = NIR::Call.new(Tango::NodeId.new("map"), "map", [source] of NIR::Expr, [] of NIR::CallTarget, block, array, nil)
    map = NIR::CollectionMap.new(fallback)
    program = NIR::Program.new([map] of NIR::Stmt)
    table = Facts::Table.new
    table.capability_conformances[map.id] = [
      Facts::CapabilityConformance.new(custom, Tango::IR::Type.klass("Enumerable", [Tango::IR::Type.int(:i32)])),
    ]

    Tango::Analysis::Passes::Blocks.run(program, table)
    Tango::Analysis::Passes::CollectionUses.run(program, table)
    Tango::Analysis::Passes::CollectionLegality.run(program, table)

    legality = table.semantic_collections[map.id]
    legality.encounter_order.should eq(Facts::EncounterOrder::Unknown)
    legality.replayability.should eq(Facts::Replayability::Unknown)
    legality.finiteness.should eq(Facts::Finiteness::Unknown)
    legality.input_cardinality.should eq(Facts::CardinalityBounds.new(nil, nil))
  end
end
