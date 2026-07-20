require "../../spec_helper"

private alias NIR = Tango::IR::NIR

private def nid(name : String) : Tango::NodeId
  Tango::NodeId.new(name)
end

private def local(id : String, name : String) : NIR::Local
  NIR::Local.new(nid(id), name, Tango::IR::Type.int(:i32), nil)
end

private def int(id : String) : NIR::IntLiteral
  NIR::IntLiteral.new(nid(id), "1", Tango::IR::Type.int(:i32), nil)
end

private def assign(id : String, target : NIR::Local, value : NIR::Expr) : NIR::Assign
  NIR::Assign.new(nid(id), target, value, Tango::IR::Type.int(:i32), nil)
end

private def block(body : Array(NIR::Stmt)) : NIR::Block
  NIR::Block.new(nid("block-#{body.object_id}"), body, nil)
end

private def run(body : Array(NIR::Stmt)) : Tango::Analysis::Facts::Table
  table = Tango::Analysis::Facts::Table.new
  Tango::Analysis::Passes::References.run(NIR::Program.new(body), table)
  table
end

private def declaration_of(table : Tango::Analysis::Facts::Table, id : String) : Tango::NodeId
  table.references[nid(id)].as(Tango::Analysis::Facts::LocalReference).declaration
end

describe Tango::Analysis::Passes::References do
  it "resolves a local read to its first assignment" do
    decl = local("decl", "x")
    read = local("read", "x")
    table = run([
      assign("a", decl, int("v")),
      read,
    ] of NIR::Stmt)

    declaration_of(table, "read").should eq(nid("decl"))
  end

  it "does not record an edge for the declaring assignment itself" do
    decl = local("decl", "x")
    table = run([assign("a", decl, int("v"))] of NIR::Stmt)

    table.references.has_key?(nid("decl")).should be_false
  end

  it "proves a never-read local can discard its write and report a lint" do
    decl = local("decl", "stale")
    table = run([assign("a", decl, int("v"))] of NIR::Stmt)

    table.unused_locals.includes?(nid("decl")).should be_true
    table.unread_local_writes.includes?(nid("decl")).should be_true
  end

  it "does not mistake a reassignment for a value read" do
    decl = local("decl", "stale")
    reassignment = local("reassign", "stale")
    table = run([
      assign("a", decl, int("v1")),
      assign("b", reassignment, int("v2")),
    ] of NIR::Stmt)

    table.unused_locals.includes?(nid("decl")).should be_true
    table.unread_local_writes.includes?(nid("decl")).should be_true
    table.unread_local_writes.includes?(nid("reassign")).should be_true
  end

  it "resolves a reassignment target to the first declaration" do
    decl = local("decl", "x")
    redecl = local("redecl", "x")
    table = run([
      assign("a", decl, int("v1")),
      assign("b", redecl, int("v2")),
    ] of NIR::Stmt)

    declaration_of(table, "redecl").should eq(nid("decl"))
  end

  it "resolves a block-arg-shadowed read to the block arg, not the outer local" do
    outer = local("outer", "n")
    arg = NIR::BlockArg.new(nid("arg"), "n", nil)
    inner_read = local("inner", "n")
    literal = NIR::BlockLiteral.new(
      nid("blk"),
      [arg],
      block([inner_read] of NIR::Stmt),
      NIR::ProcSignature.new([] of Tango::IR::Type, nil),
      Tango::IR::Type.int(:i32),
      nil,
    )
    table = run([
      assign("a", outer, int("v")),
      literal,
    ] of NIR::Stmt)

    # Scope-aware: the block arg shadows the outer `n`
    declaration_of(table, "inner").should eq(nid("arg"))
    table.binding_used?(nid("arg")).should be_true
  end

  it "records direct use facts for rescue bindings, not only assigned locals" do
    binding = local("rescue-binding", "error")
    read = local("rescue-read", "error")
    handler = NIR::ExceptionHandler.new(
      nid("handler"),
      block([] of NIR::Stmt),
      [NIR::RescueClause.new([] of Tango::IR::Type, binding, block([read] of NIR::Stmt))],
      nil,
      nil,
      Tango::IR::Type::NIL,
      nil,
    )

    table = run([handler] of NIR::Stmt)

    declaration_of(table, "rescue-read").should eq(binding.id)
    table.binding_used?(binding.id).should be_true
    table.local_reads.includes?(binding.id).should be_false
  end

  it "captures an outer local read across a block boundary" do
    outer = local("outer", "c")
    arg = NIR::BlockArg.new(nid("arg"), "n", nil)
    capture_read = local("cap", "c")
    literal = NIR::BlockLiteral.new(
      nid("blk"),
      [arg],
      block([capture_read] of NIR::Stmt),
      NIR::ProcSignature.new([] of Tango::IR::Type, nil),
      Tango::IR::Type.int(:i32),
      nil,
    )
    table = run([
      assign("a", outer, int("v")),
      literal,
    ] of NIR::Stmt)

    declaration_of(table, "cap").should eq(nid("outer"))
  end

  it "does not capture an enclosing local into a def body" do
    outer = local("outer", "x")
    param = NIR::Param.new(nid("param"), "x", Tango::IR::Type.int(:i32), nil)
    body_read = local("read", "x")
    definition = NIR::Def.new(
      nid("def"),
      "f",
      [param],
      block([body_read] of NIR::Stmt),
      Tango::IR::Type.int(:i32),
      nil,
    )
    table = run([
      assign("a", outer, int("v")),
      definition,
    ] of NIR::Stmt)

    # A def opens a fresh scope, so the read resolves to the param, never the
    # top-level `x` — defs do not close over enclosing locals.
    declaration_of(table, "read").should eq(nid("param"))
  end
end
