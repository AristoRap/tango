require "../spec_helper"

private def semantic_transform_call(kind : String?, fold : Bool = false) : Tango::IR::NIR::Call
  annotations = kind ? [Tango::IR::NIR::TargetAnnotation.new(["TangoSemantic"], [] of String, [kind])] : [] of Tango::IR::NIR::TargetAnnotation
  target = Tango::IR::NIR::CallTarget.new("transform", "Enumerable(Int32)", annotations)
  source = Tango::IR::NIR::Local.new(Tango::NodeId.new("source"), "values", Tango::IR::Type.array(Tango::IR::Type.int(:i32)), nil)
  block_body = Tango::IR::NIR::Block.new(Tango::NodeId.new("body"), [] of Tango::IR::NIR::Stmt, nil)
  signature = Tango::IR::ProcSignature.new([Tango::IR::Type.int(:i32)], Tango::IR::Type.int(:i32))
  block = Tango::IR::NIR::BlockLiteral.new(Tango::NodeId.new("block"), [] of Tango::IR::NIR::BlockArg, block_body, signature, signature.to_type, nil)
  args = [source] of Tango::IR::NIR::Expr
  args << Tango::IR::NIR::IntLiteral.new(Tango::NodeId.new("initial"), "0", Tango::IR::Type.int(:i32), nil) if fold
  Tango::IR::NIR::Call.new(
    Tango::NodeId.new("call"),
    "transform",
    args,
    [target],
    block,
    Tango::IR::Type.array(Tango::IR::Type.int(:i32)),
    nil
  )
end

describe Tango::Expansion::SemanticCalls do
  it "expands only a resolved semantic map target and retains its fallback" do
    call = semantic_transform_call("map")
    expanded = Tango::Expansion::SemanticCalls.expand(call).as(Tango::IR::NIR::CollectionMap)

    expanded.id.should eq(call.id)
    expanded.fallback.same?(call).should be_true
    expanded.source.should eq(call.args.first)
    expanded.block.should eq(call.block)
  end

  it "normalizes select and reject onto one filter operation" do
    keep = Tango::Expansion::SemanticCalls.expand(semantic_transform_call("filter_keep")).as(Tango::IR::NIR::CollectionFilter)
    reject = Tango::Expansion::SemanticCalls.expand(semantic_transform_call("filter_reject")).as(Tango::IR::NIR::CollectionFilter)

    keep.mode.keep?.should be_true
    reject.mode.reject?.should be_true
  end

  it "expands traversal and fold while retaining their ordinary calls" do
    each_call = semantic_transform_call("each")
    fold_call = semantic_transform_call("fold", fold: true)
    each = Tango::Expansion::SemanticCalls.expand(each_call).as(Tango::IR::NIR::CollectionEach)
    fold = Tango::Expansion::SemanticCalls.expand(fold_call).as(Tango::IR::NIR::CollectionFold)

    each.fallback.same?(each_call).should be_true
    fold.fallback.same?(fold_call).should be_true
    fold.initial.should eq(fold_call.args[1])
  end

  it "does not infer semantics from an unannotated method shape" do
    call = semantic_transform_call(nil)
    Tango::Expansion::SemanticCalls.expand(call).same?(call).should be_true
  end
end

describe Tango::Expansion::Driver do
  it "expands a resolved call nested inside the frontend program graph" do
    call = semantic_transform_call("map")
    target = Tango::IR::NIR::Local.new(
      Tango::NodeId.new("target"),
      "mapped",
      call.type,
      nil
    )
    assign = Tango::IR::NIR::Assign.new(
      Tango::NodeId.new("assign"),
      target,
      call,
      call.type,
      nil
    )
    program = Tango::IR::NIR::Program.new([assign] of Tango::IR::NIR::Stmt)

    expanded = Tango::Expansion::Driver.run(program)
    value = expanded.body.first.as(Tango::IR::NIR::Assign).value

    value.should be_a(Tango::IR::NIR::CollectionMap)
    value.id.should eq(call.id)
    value.as(Tango::IR::NIR::CollectionMap).fallback.name.should eq("transform")
  end
end
