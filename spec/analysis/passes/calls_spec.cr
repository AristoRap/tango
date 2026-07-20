require "../../spec_helper"

private def def_node(id : Tango::NodeId, name : String) : Tango::IR::NIR::Def
  block = Tango::IR::NIR::Block.new(Tango::NodeId.new("#{name}-body"), [] of Tango::IR::NIR::Stmt, nil)
  Tango::IR::NIR::Def.new(id, name, [] of Tango::IR::NIR::Param, block, Tango::IR::Type.int(:i32), nil)
end

private def call_node(id : Tango::NodeId, name : String, primitive : Tango::IR::NIR::Primitive? = nil) : Tango::IR::NIR::Call
  Tango::IR::NIR::Call.new(
    id, name,
    [] of Tango::IR::NIR::Expr,
    [] of Tango::IR::NIR::CallTarget,
    nil, nil, nil, primitive
  )
end

describe Tango::Analysis::Passes::Calls do
  it "records a call that names a program def" do
    def_id = Tango::NodeId.new("def")
    call_id = Tango::NodeId.new("call")
    program = Tango::IR::NIR::Program.new([
      def_node(def_id, "add"),
      call_node(call_id, "add"),
    ] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Calls.run(program, table)

    resolved = table.internal_calls[call_id]
    resolved.definition.should eq(def_id)
    resolved.name.should eq("add")
  end

  it "ignores a call that names no def" do
    call_id = Tango::NodeId.new("call")
    program = Tango::IR::NIR::Program.new([call_node(call_id, "puts")] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Calls.run(program, table)

    table.internal_calls.has_key?(call_id).should be_false
  end

  it "ignores a primitive call even when it names a def" do
    def_id = Tango::NodeId.new("def")
    call_id = Tango::NodeId.new("call")
    primitive = Tango::IR::NIR::Primitive.new(Tango::IR::NIR::Primitive::Kind::Binary, "add")
    program = Tango::IR::NIR::Program.new([
      def_node(def_id, "add"),
      call_node(call_id, "add", primitive),
    ] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Calls.run(program, table)

    table.internal_calls.has_key?(call_id).should be_false
  end

  it "resolves overloads by their concrete parameter signature" do
    int = Tango::IR::Type.int(:i32)
    string = Tango::IR::Type.string
    int_def_id = Tango::NodeId.new("int-def")
    string_def_id = Tango::NodeId.new("string-def")
    int_param = Tango::IR::NIR::Param.new(Tango::NodeId.new("int-param"), "x", int, nil)
    string_param = Tango::IR::NIR::Param.new(Tango::NodeId.new("string-param"), "x", string, nil)
    empty = ->(name : String) { Tango::IR::NIR::Block.new(Tango::NodeId.new(name), [] of Tango::IR::NIR::Stmt, nil) }
    int_def = Tango::IR::NIR::Def.new(int_def_id, "pick", [int_param], empty.call("int-body"), int, nil)
    string_def = Tango::IR::NIR::Def.new(string_def_id, "pick", [string_param], empty.call("string-body"), string, nil)
    int_arg = Tango::IR::NIR::IntLiteral.new(Tango::NodeId.new("int-arg"), "1", int, nil)
    string_arg = Tango::IR::NIR::StringLiteral.new(Tango::NodeId.new("string-arg"), "s", string, nil)
    int_call_id = Tango::NodeId.new("int-call")
    string_call_id = Tango::NodeId.new("string-call")
    int_call = Tango::IR::NIR::Call.new(int_call_id, "pick", [int_arg] of Tango::IR::NIR::Expr, [] of Tango::IR::NIR::CallTarget, nil, int, nil)
    string_call = Tango::IR::NIR::Call.new(string_call_id, "pick", [string_arg] of Tango::IR::NIR::Expr, [] of Tango::IR::NIR::CallTarget, nil, string, nil)
    program = Tango::IR::NIR::Program.new([int_def, string_def, int_call, string_call] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Calls.run(program, table)

    table.internal_calls[int_call_id].definition.should eq(int_def_id)
    table.internal_calls[string_call_id].definition.should eq(string_def_id)
  end

  it "resolves overloaded constructor dispatch to its concrete initializer" do
    int = Tango::IR::Type.int(:i32)
    string = Tango::IR::Type.string
    owner = Tango::IR::Type.klass("Box")
    empty = ->(name : String) { Tango::IR::NIR::Block.new(Tango::NodeId.new(name), [] of Tango::IR::NIR::Stmt, nil) }
    param = ->(name : String, type : Tango::IR::Type) { Tango::IR::NIR::Param.new(Tango::NodeId.new(name), name, type, nil) }
    int_def_id = Tango::NodeId.new("int-initialize")
    string_def_id = Tango::NodeId.new("string-initialize")
    int_def = Tango::IR::NIR::Def.new(
      int_def_id, "initialize", [param.call("int-self", owner), param.call("int-value", int)],
      empty.call("int-initialize-body"), Tango::IR::Type::NIL, nil,
      owner: owner, callable_kind: Tango::IR::NIR::CallableKind::Initializer
    )
    string_def = Tango::IR::NIR::Def.new(
      string_def_id, "initialize", [param.call("string-self", owner), param.call("string-value", string)],
      empty.call("string-initialize-body"), Tango::IR::Type::NIL, nil,
      owner: owner, callable_kind: Tango::IR::NIR::CallableKind::Initializer
    )
    int_new_id = Tango::NodeId.new("int-new")
    string_new_id = Tango::NodeId.new("string-new")
    int_arg = Tango::IR::NIR::IntLiteral.new(Tango::NodeId.new("int-arg"), "1", int, nil)
    string_arg = Tango::IR::NIR::StringLiteral.new(Tango::NodeId.new("string-arg"), "s", string, nil)
    int_new = Tango::IR::NIR::New.new(int_new_id, "Box", [int_arg] of Tango::IR::NIR::Expr, owner, nil)
    string_new = Tango::IR::NIR::New.new(string_new_id, "Box", [string_arg] of Tango::IR::NIR::Expr, owner, nil)
    program = Tango::IR::NIR::Program.new([int_def, string_def, int_new, string_new] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Calls.run(program, table)

    table.internal_calls[int_new_id].definition.should eq(int_def_id)
    table.internal_calls[string_new_id].definition.should eq(string_def_id)
  end
end
