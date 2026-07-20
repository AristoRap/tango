require "../../spec_helper"

describe Tango::Planning::Strategies::CollectionProductions do
  it "chooses the retained ordinary call for a semantic collection operation" do
    source = Tango::IR::NIR::Local.new(Tango::NodeId.new("source"), "values", Tango::IR::Type.array(Tango::IR::Type.int(:i32)), nil)
    body = Tango::IR::NIR::Block.new(Tango::NodeId.new("body"), [] of Tango::IR::NIR::Stmt, nil)
    signature = Tango::IR::ProcSignature.new([Tango::IR::Type.int(:i32)], Tango::IR::Type.int(:i32))
    block = Tango::IR::NIR::BlockLiteral.new(Tango::NodeId.new("block"), [] of Tango::IR::NIR::BlockArg, body, signature, signature.to_type, nil)
    array = Tango::IR::Type.array(Tango::IR::Type.int(:i32))
    fallback = Tango::IR::NIR::Call.new(Tango::NodeId.new("map"), "map", [source] of Tango::IR::NIR::Expr, [] of Tango::IR::NIR::CallTarget, block, array, nil)
    map = Tango::IR::NIR::CollectionMap.new(fallback)
    program = Tango::IR::NIR::Program.new([map] of Tango::IR::NIR::Stmt)
    plans = Tango::Planning::Plans::Table.new

    Tango::Planning::Strategies::SemanticCollections.run(program, Tango::Analysis::Facts::Table.new, plans)

    semantic_plan = plans.semantic_collections[map.id]
    semantic_plan.should be_a(Tango::Planning::Plans::MaterializeViaFallback)
    semantic_plan.result_type.should eq(array)

    release = Tango::Planning::Plans::Table.new
    Tango::Planning::Strategies::SemanticCollections.run(program, Tango::Analysis::Facts::Table.new, release, Tango::Compiler::CompilationProfile::Release)
    release.semantic_collections[map.id].should be_a(Tango::Planning::Plans::MaterializeViaFallback)
  end

  it "chooses conservative materialization for a semantic string split" do
    string = Tango::IR::NIR::StringLiteral.new(Tango::NodeId.new("string"), "a b", Tango::IR::Type.string, nil)
    array = Tango::IR::Type.array(Tango::IR::Type.string)
    split = Tango::IR::NIR::StringSplit.new(Tango::NodeId.new("split"), string, array, nil)
    program = Tango::IR::NIR::Program.new([split] of Tango::IR::NIR::Stmt)
    plans = Tango::Planning::Plans::Table.new

    Tango::Planning::Strategies::CollectionProductions.run(program, Tango::Analysis::Facts::Table.new, plans)

    production = plans.collection_productions[split.id]
    production.should be_a(Tango::Planning::Plans::MaterializedCollection)
    production.type.should eq(array)
  end

  it "records a generic size consumer and plans stored cardinality" do
    string = Tango::IR::NIR::StringLiteral.new(Tango::NodeId.new("string"), "a b", Tango::IR::Type.string, nil)
    array = Tango::IR::Type.array(Tango::IR::Type.string)
    split = Tango::IR::NIR::StringSplit.new(Tango::NodeId.new("split"), string, array, nil)
    size = Tango::IR::NIR::Size.new(Tango::NodeId.new("size"), split, Tango::IR::Type.int(:i32), nil)
    program = Tango::IR::NIR::Program.new([size] of Tango::IR::NIR::Stmt)

    facts = Tango::Analysis::Driver.run(program)
    plans = Tango::Planning::Driver.run(program, facts)

    facts.collection_uses[split.id].should eq([
      Tango::Analysis::Facts::CollectionUse.new(size.id, Tango::Analysis::Facts::CollectionConsumer::Size),
    ])
    plan = plans.cardinalities[size.id].as(Tango::Planning::Plans::StoredCardinality)
    plan.source_type.should eq(array)
    plan.source.array_elements?.should be_true

    release = Tango::Planning::Driver.run(program, facts, Tango::Compiler::CompilationProfile::Release)
    release.collection_productions[split.id].should be_a(Tango::Planning::Plans::MaterializedCollection)
    release.cardinalities[size.id].should be_a(Tango::Planning::Plans::StoredCardinality)
  end
end
