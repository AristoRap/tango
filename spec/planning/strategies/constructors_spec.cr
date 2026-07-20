require "../../spec_helper"

private def constructor_node(id : Tango::NodeId, owner : Tango::IR::Type, arg : Tango::IR::NIR::Expr) : Tango::IR::NIR::New
  Tango::IR::NIR::New.new(id, expect_present(owner.name), [arg] of Tango::IR::NIR::Expr, owner, nil)
end

describe Tango::Planning::Strategies::Constructors do
  it "reads the concrete initializer's def plan" do
    owner = Tango::IR::Type.klass("Box")
    int = Tango::IR::Type.int(:i32)
    id = Tango::NodeId.new("new")
    definition_id = Tango::NodeId.new("initialize")
    arg = Tango::IR::NIR::IntLiteral.new(Tango::NodeId.new("arg"), "1", int, nil)
    program = Tango::IR::NIR::Program.new([constructor_node(id, owner, arg)] of Tango::IR::NIR::Stmt)
    facts = Tango::Analysis::Facts::Table.new
    signature = Tango::Analysis::Facts::CallableSignature.new("initialize", [owner, int])
    facts.internal_calls[id] = Tango::Analysis::Facts::ResolvedCall.new(definition_id, signature)
    plans = Tango::Planning::Plans::Table.new
    plans.monomorphs[definition_id] = Tango::Planning::Plans::DefPlan.new("initialize__Box__Int32")

    Tango::Planning::Strategies::Constructors.run(program, facts, plans)

    plans.constructors[id].initialize_name.should eq("initialize__Box__Int32")
  end

  it "does not reconstruct an initializer name when its def has no plan" do
    owner = Tango::IR::Type.klass("Box")
    int = Tango::IR::Type.int(:i32)
    id = Tango::NodeId.new("new")
    definition_id = Tango::NodeId.new("initialize")
    arg = Tango::IR::NIR::IntLiteral.new(Tango::NodeId.new("arg"), "1", int, nil)
    program = Tango::IR::NIR::Program.new([constructor_node(id, owner, arg)] of Tango::IR::NIR::Stmt)
    facts = Tango::Analysis::Facts::Table.new
    signature = Tango::Analysis::Facts::CallableSignature.new("initialize", [owner, int])
    facts.internal_calls[id] = Tango::Analysis::Facts::ResolvedCall.new(definition_id, signature)
    plans = Tango::Planning::Plans::Table.new

    Tango::Planning::Strategies::Constructors.run(program, facts, plans)

    plans.constructors.has_key?(id).should be_false
  end
end
