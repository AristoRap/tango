require "../../spec_helper"

private alias NIR = Tango::IR::NIR

private def collect_block_literals(node : Tango::IR::NIR::Stmt, into : Array(Tango::IR::NIR::BlockLiteral)) : Nil
  into << node if node.is_a?(Tango::IR::NIR::BlockLiteral)
  Tango::IR::NIR::Walk.children(node).each { |child| collect_block_literals(child, into) }
end

describe Tango::Analysis::Passes::Blocks do
  it "keeps a nested block's capture out of its enclosing block facts" do
    snapshot = Tango.snapshot(<<-TN, filename: "nested_capture.tn")
      def apply(& : Int32 -> Int32) : Int32
        yield 1
      end

      captured = 10
      apply do |outer|
        apply { |inner| inner + captured }
        outer
      end
      TN

    program = expect_present(snapshot.nir)
    facts = expect_present(snapshot.facts)
    blocks = [] of Tango::IR::NIR::BlockLiteral
    Tango::IR::NIR::Walk.children(program).each { |node| collect_block_literals(node, blocks) }

    outer = expect_present(blocks.find { |block| block.args.first?.try(&.name) == "outer" })
    inner = expect_present(blocks.find { |block| block.args.first?.try(&.name) == "inner" })
    declaration = expect_present(program.body.compact_map(&.as?(NIR::Assign)).find { |assign| assign.target.as?(NIR::Local).try(&.name) == "captured" }).target
    facts.blocks[outer.id].captured.map(&.name).should_not contain("captured")
    facts.blocks[inner.id].captured.map(&.name).should contain("captured")
    expect_present(facts.blocks[inner.id].captured.find(&.name.==("captured"))).declaration.should eq(declaration.id)
  end

  it "distinguishes same-named spawning and synchronous defs by resolved identity" do
    id = ->(name : String) { Tango::NodeId.new(name) }
    signature = NIR::ProcSignature.new([] of Tango::IR::Type, nil)
    spawning_param = NIR::BlockParam.new(id.call("spawning-param"), "block", signature, nil)
    synchronous_param = NIR::BlockParam.new(id.call("synchronous-param"), "block", signature, nil)
    spawning_proc = NIR::Local.new(id.call("spawning-proc"), "block", signature.to_type, nil)
    spawning_body = NIR::Block.new(id.call("spawning-body"), [
      NIR::Spawn.new(id.call("spawn"), spawning_proc, nil, nil),
    ] of NIR::Stmt, nil)
    synchronous_body = NIR::Block.new(id.call("synchronous-body"), [] of NIR::Stmt, nil)
    spawning_def = NIR::Def.new(id.call("spawning-def"), "run", [] of NIR::Param, spawning_body, nil, nil, block_param: spawning_param)
    synchronous_def = NIR::Def.new(id.call("synchronous-def"), "run", [] of NIR::Param, synchronous_body, nil, nil, block_param: synchronous_param)

    escaping_literal = NIR::BlockLiteral.new(id.call("escaping-literal"), [] of NIR::BlockArg, NIR::Block.new(id.call("escaping-body"), [] of NIR::Stmt, nil), signature, nil, nil)
    local_literal = NIR::BlockLiteral.new(id.call("local-literal"), [] of NIR::BlockArg, NIR::Block.new(id.call("local-body"), [] of NIR::Stmt, nil), signature, nil, nil)
    escaping_call = NIR::Call.new(id.call("escaping-call"), "run", [] of NIR::Expr, [] of NIR::CallTarget, escaping_literal, nil, nil)
    local_call = NIR::Call.new(id.call("local-call"), "run", [] of NIR::Expr, [] of NIR::CallTarget, local_literal, nil, nil)
    program = NIR::Program.new([spawning_def, synchronous_def, escaping_call, local_call] of NIR::Stmt)
    facts = Tango::Analysis::Facts::Table.new
    callable = Tango::Analysis::Facts::CallableSignature.new("run", [signature.to_type])
    facts.internal_calls[escaping_call.id] = Tango::Analysis::Facts::ResolvedCall.new(spawning_def.id, callable)
    facts.internal_calls[local_call.id] = Tango::Analysis::Facts::ResolvedCall.new(synchronous_def.id, callable)

    Tango::Analysis::Passes::Blocks.run(program, facts)

    facts.blocks[escaping_literal.id].escapes.should be_true
    facts.blocks[local_literal.id].escapes.should be_false
  end

  it "records the compiler-owned StringEachChar block through the shared facts seam" do
    id = ->(name : String) { Tango::NodeId.new(name) }
    string = NIR::StringLiteral.new(id.call("string"), "é", Tango::IR::Type.string, nil)
    arg = NIR::BlockArg.new(id.call("char"), "char", nil)
    block = NIR::BlockLiteral.new(
      id.call("block"),
      [arg],
      NIR::Block.new(id.call("body"), [] of NIR::Stmt, nil),
      NIR::ProcSignature.new([Tango::IR::Type.char] of Tango::IR::Type, nil),
      nil,
      nil
    )
    each = NIR::StringEachChar.new(id.call("each"), string, block, Tango::IR::Type::NIL, nil)
    facts = Tango::Analysis::Facts::Table.new

    Tango::Analysis::Passes::Blocks.run(NIR::Program.new([each] of NIR::Stmt), facts)

    facts.blocks[block.id].captured.should be_empty
    facts.blocks[block.id].escapes.should be_false
  end
end
