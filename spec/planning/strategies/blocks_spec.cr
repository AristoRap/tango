require "../../spec_helper"

describe Tango::Planning::Strategies::Blocks do
  it "selects the existing yield protocol for StringEachChar callbacks" do
    id = ->(name : String) { Tango::NodeId.new(name) }
    string = Tango::IR::NIR::StringLiteral.new(id.call("string"), "é", Tango::IR::Type.string, nil)
    arg = Tango::IR::NIR::BlockArg.new(id.call("char"), "char", nil)
    block = Tango::IR::NIR::BlockLiteral.new(
      id.call("block"),
      [arg],
      Tango::IR::NIR::Block.new(id.call("body"), [] of Tango::IR::NIR::Stmt, nil),
      Tango::IR::NIR::ProcSignature.new([Tango::IR::Type.char] of Tango::IR::Type, nil),
      nil,
      nil
    )
    each = Tango::IR::NIR::StringEachChar.new(id.call("each"), string, block, Tango::IR::Type::NIL, nil)
    facts = Tango::Analysis::Facts::Table.new
    facts.blocks[block.id] = Tango::Analysis::Facts::BlockFacts.new([] of Tango::Analysis::Facts::Capture, false)
    plans = Tango::Planning::Plans::Table.new

    Tango::Planning::Strategies::Blocks.run(Tango::IR::NIR::Program.new([each] of Tango::IR::NIR::Stmt), facts, plans)

    plans.closures[block.id].mode.should eq(Tango::Planning::Plans::BlockMode::Protocol)
  end
end
