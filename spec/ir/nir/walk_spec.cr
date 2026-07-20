require "../../spec_helper"

private alias NIR = Tango::IR::NIR

private def node_id(value : String) : Tango::NodeId
  Tango::NodeId.new(value)
end

private def int_literal(value : String = "1") : NIR::IntLiteral
  NIR::IntLiteral.new(node_id("int-#{value}"), value, Tango::IR::Type.int(:i32), nil)
end

private def local(name : String = "x") : NIR::Local
  NIR::Local.new(node_id("local-#{name}"), name, nil, nil)
end

private def block(body : Array(NIR::Stmt) = [] of NIR::Stmt, label : String = "block") : NIR::Block
  NIR::Block.new(node_id(label), body, nil)
end

private def call(args : Array(NIR::Expr) = [] of NIR::Expr, block : NIR::BlockLiteral? = nil) : NIR::Call
  NIR::Call.new(node_id("call"), "puts", args, [] of NIR::CallTarget, block, nil, nil)
end

describe Tango::IR::NIR::Walk do
  it "returns the program body as children" do
    stmt = int_literal
    program = NIR::Program.new([stmt] of NIR::Stmt)

    NIR::Walk.children(program).should eq([stmt])
  end

  it "returns the block body as children" do
    stmt = int_literal
    NIR::Walk.children(block([stmt] of NIR::Stmt)).should eq([stmt])
  end

  it "returns literal, local, param, block arg, and unsupported nodes as leaves" do
    leaves = [
      int_literal,
      NIR::StringLiteral.new(node_id("s"), "hi", nil, nil),
      NIR::BoolLiteral.new(node_id("b"), true, nil, nil),
      local,
      NIR::ClassRef.new(node_id("class-ref"), "File", Tango::IR::Type.klass("File"), nil),
      NIR::Param.new(node_id("param"), "x", nil, nil),
      NIR::BlockArg.new(node_id("block-arg"), "n", nil),
      NIR::UnsupportedExpr.new(node_id("unsupported"), "Crystal::MultiAssign", nil, nil),
    ] of NIR::Stmt

    leaves.each do |leaf|
      NIR::Walk.children(leaf).should be_empty
      NIR::Walk.non_binding_children(leaf).should be_empty
    end
  end

  it "includes the assign target in children but not in non_binding_children" do
    target = local
    value = int_literal
    assign = NIR::Assign.new(node_id("assign"), target, value, nil, nil)

    NIR::Walk.children(assign).should eq([target, value])
    NIR::Walk.non_binding_children(assign).should eq([value] of NIR::Stmt)
  end

  it "includes cond and both branches for if" do
    cond = local("t")
    then_branch = block(label: "then")
    else_branch = block(label: "else")
    node = NIR::If.new(node_id("if"), cond, then_branch, else_branch, nil, nil)

    NIR::Walk.children(node).should eq([cond, then_branch, else_branch])
    NIR::Walk.non_binding_children(node).should eq([cond, then_branch, else_branch])
  end

  it "omits a missing else branch for if" do
    cond = local("t")
    then_branch = block(label: "then")
    node = NIR::If.new(node_id("if"), cond, then_branch, nil, nil, nil)

    NIR::Walk.children(node).should eq([cond, then_branch])
  end

  it "includes cond and body for while" do
    cond = local("t")
    body = block(label: "body")
    node = NIR::While.new(node_id("while"), cond, body, nil)

    NIR::Walk.children(node).should eq([cond, body])
    NIR::Walk.non_binding_children(node).should eq([cond, body])
  end

  it "includes def params in children but not in non_binding_children" do
    param = NIR::Param.new(node_id("param"), "x", nil, nil)
    body = block(label: "def-body")
    node = NIR::Def.new(node_id("def"), "foo", [param], body, nil, nil)

    NIR::Walk.children(node).should eq([param, body])
    NIR::Walk.non_binding_children(node).should eq([body] of NIR::Stmt)
  end

  it "walks class field initializers and their values" do
    field = Tango::IR::Field.new("x", Tango::IR::Type.int(:i32))
    value = int_literal
    initializer = NIR::FieldInitializer.new(node_id("field-initializer"), field, value, nil)
    node = NIR::Class.new(node_id("class"), "Foo", nil, [field], nil, initializers: [initializer])

    NIR::Walk.children(node).should eq([initializer] of NIR::Stmt)
    NIR::Walk.non_binding_children(node).should eq([initializer] of NIR::Stmt)
    NIR::Walk.children(initializer).should eq([value] of NIR::Stmt)
  end

  it "includes block literal args in children but not in non_binding_children" do
    arg = NIR::BlockArg.new(node_id("block-arg"), "n", nil)
    body = block(label: "block-body")
    signature = NIR::ProcSignature.new([Tango::IR::Type.int(:i32)] of Tango::IR::Type, Tango::IR::Type.int(:i32))
    node = NIR::BlockLiteral.new(node_id("block-literal"), [arg], body, signature, nil, nil)

    NIR::Walk.children(node).should eq([arg, body])
    NIR::Walk.non_binding_children(node).should eq([body] of NIR::Stmt)
  end

  it "includes call args and the inline block as children" do
    arg = int_literal
    inline = NIR::BlockLiteral.new(node_id("block-literal"), [] of NIR::BlockArg, block(label: "block-body"), NIR::ProcSignature.new([] of Tango::IR::Type, nil), nil, nil)
    node = call([arg] of NIR::Expr, inline)

    NIR::Walk.children(node).should eq([arg, inline])
    NIR::Walk.non_binding_children(node).should eq([arg, inline])
  end

  it "walks a class dispatch receiver separately from runtime call arguments" do
    receiver = NIR::ClassRef.new(node_id("class-ref"), "File", Tango::IR::Type.klass("File"), nil)
    arg = int_literal
    node = NIR::Call.new(node_id("call"), "read", [arg] of NIR::Expr, [] of NIR::CallTarget, nil, nil, nil, dispatch_receiver: receiver)

    NIR::Walk.children(node).should eq([receiver, arg] of NIR::Stmt)
    node.args.should eq([arg] of NIR::Expr)
  end

  it "omits a missing inline block for calls" do
    arg = int_literal
    NIR::Walk.children(call([arg] of NIR::Expr)).should eq([arg] of NIR::Stmt)
  end

  it "walks string receivers, indexes, and iteration blocks" do
    string = NIR::StringLiteral.new(node_id("string"), "é", Tango::IR::Type.string, nil)
    index = int_literal("0")
    character = NIR::StringCharAt.new(node_id("char-at"), string, index, Tango::IR::Type.char, nil)
    NIR::Walk.children(character).should eq([string, index] of NIR::Stmt)

    arg = NIR::BlockArg.new(node_id("char"), "char", nil)
    literal = NIR::BlockLiteral.new(node_id("char-block"), [arg], block(label: "char-body"), NIR::ProcSignature.new([Tango::IR::Type.char] of Tango::IR::Type, nil), nil, nil)
    iteration = NIR::StringEachChar.new(node_id("each-char"), string, literal, Tango::IR::Type::NIL, nil)
    NIR::Walk.children(iteration).should eq([string, literal] of NIR::Stmt)

    separator = NIR::StringLiteral.new(node_id("separator"), ";", Tango::IR::Type.string, nil)
    split = NIR::StringSplit.new(node_id("split"), string, Tango::IR::Type.array(Tango::IR::Type.string), nil, separator)
    NIR::Walk.children(split).should eq([string, separator] of NIR::Stmt)

    parse = NIR::StringToFloat.new(node_id("parse"), string, Tango::IR::Type.float64, nil)
    NIR::Walk.children(parse).should eq([string] of NIR::Stmt)
  end
end
