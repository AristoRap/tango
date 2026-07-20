require "../../spec_helper"

private alias LIR = Tango::IR::LIR

private def int_const(value : String = "1") : LIR::IntConst
  LIR::IntConst.new(value)
end

private def discard(value : LIR::Value = int_const) : LIR::Discard
  LIR::Discard.new(value)
end

describe LIR::Walk do
  it "walks mixed select and handler children in source order" do
    channel = LIR::Temp.new("ch")
    sent = int_const("3")
    arm_stmt = discard(int_const("4"))
    default_stmt = discard(int_const("5"))
    arm = LIR::Select::Arm.new(LIR::Select::Arm::Kind::Send, channel, sent, nil, Tango::IR::Type.int(:i32), [arm_stmt] of LIR::Stmt)
    select_stmt = LIR::Select.new([arm], [default_stmt] of LIR::Stmt)

    LIR::Walk.children(select_stmt).should eq([channel, sent, arm_stmt, default_stmt] of LIR::Walk::Node)

    body = discard(int_const("6"))
    clause_body = discard(int_const("7"))
    else_body = discard(int_const("8"))
    ensure_body = discard(int_const("9"))
    clause = LIR::RescueClause(Array(LIR::Stmt)).new([] of Tango::IR::Type, nil, [clause_body] of LIR::Stmt, true)
    handler = LIR::Handler.new([body] of LIR::Stmt, [clause], [else_body] of LIR::Stmt, [ensure_body] of LIR::Stmt)

    LIR::Walk.children(handler).should eq([body, clause_body, else_body, ensure_body] of LIR::Walk::Node)
  end

  it "walks statement and terminal-value children in rescue values" do
    body_stmt = discard(int_const("1"))
    body_value = int_const("2")
    clause_stmt = discard(int_const("3"))
    clause_value = int_const("4")
    else_stmt = discard(int_const("5"))
    else_value = int_const("6")
    ensure_stmt = discard(int_const("7"))
    body = LIR::RescueValue::Arm.new([body_stmt] of LIR::Stmt, body_value)
    clause_arm = LIR::RescueValue::Arm.new([clause_stmt] of LIR::Stmt, clause_value)
    else_arm = LIR::RescueValue::Arm.new([else_stmt] of LIR::Stmt, else_value)
    clause = LIR::RescueClause(LIR::RescueValue::Arm).new([] of Tango::IR::Type, nil, clause_arm, true)
    rescue_value = LIR::RescueValue.new(body, [clause], else_arm, [ensure_stmt] of LIR::Stmt, Tango::IR::Type.int(:i32))

    LIR::Walk.children(rescue_value).should eq([
      body_stmt,
      body_value,
      clause_stmt,
      clause_value,
      else_stmt,
      else_value,
      ensure_stmt,
    ] of LIR::Walk::Node)
  end

  it "walks nested values hidden behind collection and closure nodes" do
    call = LIR::Call.new("index", [int_const("1")] of LIR::Value)
    array_get = LIR::ArrayGet.new(LIR::Temp.new("items"), call, Tango::IR::Type.int(:i32))
    LIR::Walk.children(array_get).should eq([array_get.array, call] of LIR::Walk::Node)

    closure_stmt = discard(call)
    closure = LIR::Closure.new([] of LIR::Param, nil, [closure_stmt] of LIR::Stmt)
    LIR::Walk.children(closure).should eq([closure_stmt] of LIR::Walk::Node)

    string = LIR::StringConst.new("é")
    character = LIR::StringCharAt.new(string, int_const("0"))
    LIR::Walk.children(character).should eq([string, character.index] of LIR::Walk::Node)

    parse = LIR::StringToFloat.new(string)
    LIR::Walk.children(parse).should eq([string] of LIR::Walk::Node)

    separator = LIR::StringConst.new(";")
    split = LIR::MaterializedStringSplit.new(string, Tango::IR::Type.array(Tango::IR::Type.string), separator)
    LIR::Walk.children(split).should eq([string, separator] of LIR::Walk::Node)

    each_char = LIR::StringEachChar.new(string, closure)
    LIR::Walk.children(each_char).should eq([string, closure] of LIR::Walk::Node)
  end

  it "returns scalar and allocation nodes as leaves" do
    leaves = [
      int_const,
      LIR::StringConst.new("x"),
      LIR::BoolConst.new(true),
      LIR::NilConst.new,
      LIR::Temp.new("x"),
      LIR::Alloc.new("Thing"),
      LIR::MakeMutex.new(Tango::IR::Type.klass("Mutex")),
      LIR::ArrayNew.new(Tango::IR::Type.unknown, Tango::IR::Type.unknown),
      LIR::HashNew.new(Tango::IR::Type.unknown),
    ] of LIR::Value

    leaves.each { |leaf| LIR::Walk.children(leaf).should be_empty }
  end
end
