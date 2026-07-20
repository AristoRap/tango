require "../../spec_helper"

describe Tango::Analysis::Passes::Types do
  it "records expression type names into the fact table" do
    id = Tango::NodeId.new("expression-1")
    literal = Tango::IR::NIR::IntLiteral.new(id, "1", Tango::IR::Type.int(:i32), nil)
    program = Tango::IR::NIR::Program.new([literal] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Types.run(program, table)

    table.types.expressions[id].to_s.should eq("Int32")
  end

  it "descends into call arguments" do
    arg_id = Tango::NodeId.new("arg")
    call_id = Tango::NodeId.new("call")
    arg = Tango::IR::NIR::IntLiteral.new(arg_id, "1", Tango::IR::Type.int(:i32), nil)
    call = Tango::IR::NIR::Call.new(
      call_id, "puts",
      [arg] of Tango::IR::NIR::Expr,
      [] of Tango::IR::NIR::CallTarget,
      nil, nil, nil
    )
    program = Tango::IR::NIR::Program.new([call] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Types.run(program, table)

    table.types.expressions[arg_id].to_s.should eq("Int32")
  end

  it "records concrete and nested array types for representation planning" do
    i32 = Tango::IR::Type.int(:i32)
    inner = Tango::IR::Type.array(i32)
    outer = Tango::IR::Type.array(inner)
    node = Tango::IR::NIR::ArrayNew.new(Tango::NodeId.new("array"), inner, outer, nil)
    table = Tango::Analysis::Facts::Table.new

    Tango::Analysis::Passes::Types.run(Tango::IR::NIR::Program.new([node] of Tango::IR::NIR::Stmt), table)

    table.types.arrays.should contain(outer)
    table.types.arrays.should contain(inner)
  end
end
