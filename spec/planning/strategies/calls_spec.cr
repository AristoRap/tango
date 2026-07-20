require "../../spec_helper"

private def call_node(id : Tango::NodeId, name : String = "puts", args : Array(Tango::IR::NIR::Expr) = [] of Tango::IR::NIR::Expr) : Tango::IR::NIR::Call
  Tango::IR::NIR::Call.new(
    id, name,
    args,
    [] of Tango::IR::NIR::CallTarget,
    nil, nil, nil
  )
end

describe Tango::Planning::Strategies::Calls do
  it "plans an internal call from an internal_call fact" do
    id = Tango::NodeId.new("call")
    definition_id = Tango::NodeId.new("definition")
    program = Tango::IR::NIR::Program.new([call_node(id, "add")] of Tango::IR::NIR::Stmt)

    facts = Tango::Analysis::Facts::Table.new
    signature = Tango::Analysis::Facts::CallableSignature.new("add", [] of Tango::IR::Type)
    facts.internal_calls[id] = Tango::Analysis::Facts::ResolvedCall.new(definition_id, signature)

    table = Tango::Planning::Plans::Table.new
    table.monomorphs[definition_id] = Tango::Planning::Plans::DefPlan.new("add")
    Tango::Planning::Strategies::Calls.run(program, facts, table)

    plan = table.calls[id].as(Tango::Planning::Plans::InternalCall)
    plan.name.should eq("add")
  end

  it "does not reconstruct an internal target when its def has no plan" do
    id = Tango::NodeId.new("call")
    definition_id = Tango::NodeId.new("definition")
    program = Tango::IR::NIR::Program.new([call_node(id, "add")] of Tango::IR::NIR::Stmt)
    facts = Tango::Analysis::Facts::Table.new
    signature = Tango::Analysis::Facts::CallableSignature.new("add", [] of Tango::IR::Type)
    facts.internal_calls[id] = Tango::Analysis::Facts::ResolvedCall.new(definition_id, signature)

    table = Tango::Planning::Plans::Table.new
    Tango::Planning::Strategies::Calls.run(program, facts, table)

    table.calls[id].should be_a(Tango::Planning::Plans::UnsupportedCall)
  end

  it "plans an external Go call from a GoExternal fact" do
    id = Tango::NodeId.new("call")
    program = Tango::IR::NIR::Program.new([call_node(id)] of Tango::IR::NIR::Stmt)

    facts = Tango::Analysis::Facts::Table.new
    facts.go_externals[id] = [Tango::Analysis::Facts::GoExternal.new("fmt", "Println")]

    table = Tango::Planning::Plans::Table.new
    Tango::Planning::Strategies::Calls.run(program, facts, table)

    plan = table.calls[id].as(Tango::Planning::Plans::ExternalGo)
    plan.callee.package_name.should eq("fmt")
    plan.callee.name.should eq("Println")
  end

  it "plans an unsupported call when there is no fact" do
    id = Tango::NodeId.new("call")
    program = Tango::IR::NIR::Program.new([call_node(id)] of Tango::IR::NIR::Stmt)

    facts = Tango::Analysis::Facts::Table.new
    table = Tango::Planning::Plans::Table.new
    Tango::Planning::Strategies::Calls.run(program, facts, table)

    table.calls[id].should be_a(Tango::Planning::Plans::UnsupportedCall)
  end

  it "recurses into call arguments" do
    inner_id = Tango::NodeId.new("inner")
    outer_id = Tango::NodeId.new("outer")
    inner = call_node(inner_id)
    outer = call_node(outer_id, args: [inner] of Tango::IR::NIR::Expr)
    program = Tango::IR::NIR::Program.new([outer] of Tango::IR::NIR::Stmt)

    facts = Tango::Analysis::Facts::Table.new
    facts.go_externals[inner_id] = [Tango::Analysis::Facts::GoExternal.new(nil, "puts")]

    table = Tango::Planning::Plans::Table.new
    Tango::Planning::Strategies::Calls.run(program, facts, table)

    table.calls[inner_id].should be_a(Tango::Planning::Plans::ExternalGo)
    table.calls[outer_id].should be_a(Tango::Planning::Plans::UnsupportedCall)
  end
end
