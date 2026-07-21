require "../../spec_helper"

private alias NIR = Tango::IR::NIR

private def nir_body(source : String) : Array(NIR::Stmt)
  snapshot = Tango.snapshot(source, filename: "to_nir_spec.tn")
  program = snapshot.nir
  program.should_not be_nil, "expected NIR, got diagnostics: #{snapshot.diagnostics.join(", ")}"
  expect_present(program).body
end

describe Tango::Frontend::Crystal::ToNIR do
  it "normalizes scalar-system intrinsics, powers, and checked float conversion" do
    program = expect_present(Tango.snapshot("x = 0.0\ni = 1_i8\nputs(-x)\nputs(-i)\nputs(2.0 ** 3)\nputs(1.0.to_i8)\nputs(2_i8 ** 3_u16)", filename: "scalar_nir.tn").nir)
    pending = NIR::Walk.children(program)
    kinds = [] of NIR::Primitive::Kind
    until pending.empty?
      node = pending.shift
      node.as?(NIR::Call).try(&.primitive).try { |primitive| kinds << primitive.kind }
      pending.concat(NIR::Walk.children(node))
    end

    kinds.should contain(NIR::Primitive::Kind::FloatIntrinsic)
    kinds.should contain(NIR::Primitive::Kind::CheckedNegate)
    kinds.should contain(NIR::Primitive::Kind::FloatPower)
    kinds.should contain(NIR::Primitive::Kind::CheckedFloatConvert)
    kinds.should contain(NIR::Primitive::Kind::IntegerPower)
  end

  it "normalizes the integer-system families without width-specific NIR nodes" do
    body = nir_body("puts(1_u64 &+ 2_u64)\nputs(3_i16 & 1_i16)\nputs(~4_i8)\nputs(5_u32 << 2_u8)\nputs(6_i64.to_u16!)\nputs(\"7\".to_u16)")
    calls = body.compact_map(&.as?(NIR::Call))
    values = calls.select(&.name.==("puts")).map { |call| call.args.first.as(NIR::Call) }

    values.first(5).map { |value| value.primitive.try(&.kind) }.should eq([
      NIR::Primitive::Kind::WrappingArithmetic,
      NIR::Primitive::Kind::Bitwise,
      NIR::Primitive::Kind::BitwiseNot,
      NIR::Primitive::Kind::IntegerShift,
      NIR::Primitive::Kind::WrappingIntegerConvert,
    ])
    pending = NIR::Walk.children(expect_present(Tango.snapshot("puts \"7\".to_u16").nir))
    found_parse = false
    until pending.empty?
      node = pending.shift
      found_parse ||= node.is_a?(NIR::StringToInteger)
      pending.concat(NIR::Walk.children(node))
    end
    found_parse.should be_true
  end

  it "normalizes report comparison, conversion, and rounding through shared primitive calls" do
    body = nir_body("puts(\"Berlin\" <=> \"Amsterdam\")\nputs 3.to_f\nputs 11.5.round")
    values = body.map(&.as(NIR::Call)).map { |call| call.args.first.as(NIR::Call) }

    values.map { |value| value.primitive.try(&.kind) }.should eq([
      NIR::Primitive::Kind::StringCompare,
      NIR::Primitive::Kind::NumericConvert,
      NIR::Primitive::Kind::FloatIntrinsic,
    ])
    values.map(&.args.size).should eq([2, 1, 1])
    values.map(&.type).should eq([
      Tango::IR::Type.int(:i32),
      Tango::IR::Type.float64,
      Tango::IR::Type.float64,
    ])
  end

  it "normalizes the Float64 ordering forced by weather extrema as binary operations" do
    body = nir_body("puts(1.0 < 2.0)\nputs(3.0 > 4.0)")
    comparisons = body.map(&.as(NIR::Call)).map { |call| call.args.first.as(NIR::Call) }

    comparisons.map(&.name).should eq(["<", ">"])
    comparisons.each do |comparison|
      comparison.primitive.try(&.kind.binary?).should be_true
      comparison.args.map(&.type).should eq([Tango::IR::Type.float64, Tango::IR::Type.float64])
      comparison.type.should eq(Tango::IR::Type.bool)
    end
  end

  it "normalizes exact separator splitting and decimal parsing as string operations" do
    body = nir_body("fields = \"Amsterdam;12.5\".split(\";\")\nmeasurement = fields[1].to_f")
    assigns = body.compact_map(&.as?(NIR::Assign))

    split = assigns.find! { |assign| assign.target.as(NIR::Local).name == "fields" }.value.as(NIR::StringSplit)
    split.string.as(NIR::StringLiteral).value.should eq("Amsterdam;12.5")
    split.separator.as(NIR::StringLiteral).value.should eq(";")

    parse = assigns.find! { |assign| assign.target.as(NIR::Local).name == "measurement" }.value.as(NIR::StringToFloat)
    parse.string.should be_a(NIR::IndexedRead)
    parse.type.should eq(Tango::IR::Type.float64)
  end

  it "keeps class-method dispatch identity without a runtime metaclass argument" do
    body = nir_body(<<-TN)
      class Reader
        def self.read(path : String) : String
          path
        end
      end

      puts Reader.read("measurements.txt")
      TN

    call = body.compact_map(&.as?(NIR::Call)).find!(&.name.==("puts")).args.first.as(NIR::Call)
    call.name.should eq("read")
    call.args.map(&.type).should eq([Tango::IR::Type.string])
    receiver = expect_present(call.dispatch_receiver)
    receiver.name.should eq("Reader")
    receiver.type.should eq(Tango::IR::Type.klass("Reader"))
    site = expect_present(call.method_site)
    site.kind.class_method?.should be_true
    site.owner.should eq(Tango::IR::Type.klass("Reader"))
  end

  it "consumes typed accessor expansion as ordinary defs with field initializers" do
    body = nir_body(<<-TN)
      class Settings
        getter name : String = "tango"
        setter threshold : Int32 = 1
        property count : Int32 = 2
      end

      settings = Settings.new
      puts settings.name
      puts(settings.threshold = 3)
      puts settings.count
      settings.count = 4
      TN

    klass = body.compact_map(&.as?(NIR::Class)).first
    klass.fields.map(&.name).should eq(%w(name threshold count))
    klass.initializers.map(&.name).should eq(%w(name threshold count))
    klass.initializers.map(&.value).map(&.class).should eq([
      NIR::StringLiteral,
      NIR::IntLiteral,
      NIR::IntLiteral,
    ])

    methods = body.compact_map(&.as?(NIR::Def)).map(&.name)
    methods.should contain("name")
    methods.should contain("threshold=")
    methods.should contain("count")
    methods.should contain("count=")
  end

  it "preserves both numeric sleep overloads as one external binding" do
    calls = nir_body("sleep 0\nsleep 0.0").map(&.as(NIR::Call))

    calls.map { |call| call.args.first.type }.should eq([
      Tango::IR::Type.int(:i32),
      Tango::IR::Type.float64,
    ])
    calls.each do |call|
      call.targets.any? { |target| target.annotations.any? { |ann| ann.path == ["Go"] && ann.string_args == ["tangoSleep"] } }.should be_true
    end
  end

  it "preserves Crystal's selected constructor type for an autocast numeric literal" do
    body = nir_body(<<-TN)
      class StationStats
        getter sum : Float64

        def initialize(measurement : Float64)
          @sum = measurement
        end
      end

      stats = StationStats.new(10)
      TN

    construction = body.compact_map(&.as?(NIR::Assign)).first.value.as(NIR::New)
    argument = construction.args.first.as(NIR::FloatLiteral)
    argument.value.should eq("10")
    argument.type.should eq(Tango::IR::Type.float64)
  end

  it "translates raise and rescue/ensure as typed exception nodes" do
    body = nir_body(<<-TN)
      begin
        raise "boom"
      rescue ex : OverflowError
        puts ex.message
      ensure
        puts "done"
      end
      TN

    handler = body.first.as(NIR::ExceptionHandler)
    handler.body.body.first.as(NIR::Raise).kind.should eq(NIR::Raise::Kind::Message)
    handler.clauses.first.types.map(&.to_s).should eq(["OverflowError"])
    expect_present(handler.clauses.first.binding).name.should eq("ex")
    handler.ensure_branch.should_not be_nil
  end

  it "keeps a raised builtin exception constructor structured" do
    body = nir_body(<<-TN)
      begin
        raise OverflowError.new("custom")
      rescue ex : OverflowError
        puts ex.message
      end
      TN

    raised = body.first.as(NIR::ExceptionHandler).body.body.first.as(NIR::Raise)
    raised.kind.should eq(NIR::Raise::Kind::Exception)
    value = raised.value.as(NIR::ExceptionNew)
    value.class_name.should eq("OverflowError")
    expect_present(value.message).as(NIR::StringLiteral).value.should eq("custom")
  end

  it "translates an assignment to a local" do
    body = nir_body("x = 1")

    assign = body.first.as(NIR::Assign)
    assign.target.as(NIR::Local).name.should eq("x")
    assign.value.as(NIR::IntLiteral).value.should eq("1")
    assign.span.should_not be_nil
  end

  it "translates a local reference as a call argument" do
    body = nir_body("x = 1\nputs x")

    call = body[1].as(NIR::Call)
    call.name.should eq("puts")
    call.args.first.as(NIR::Local).name.should eq("x")
  end

  it "translates if/else into branch blocks" do
    body = nir_body(<<-TN)
      t = true
      if t
        puts 1
      else
        puts 2
      end
      TN

    node = body[1].as(NIR::If)
    node.cond.as(NIR::Local).name.should eq("t")
    node.then_branch.body.first.as(NIR::Call).name.should eq("puts")
    expect_present(node.else_branch).body.first.as(NIR::Call).name.should eq("puts")
  end

  it "normalizes a bare unless into an If with an empty then branch" do
    body = nir_body(<<-TN)
      x = 5
      unless x < 2
        puts x
      end
      TN

    node = body[1].as(NIR::If)
    node.cond.as(NIR::Call).name.should eq("<")
    node.then_branch.body.should be_empty
    expect_present(node.else_branch).body.first.as(NIR::Call).name.should eq("puts")
  end

  it "normalizes unless/else into an If with swapped branches" do
    body = nir_body(<<-TN)
      x = 5
      unless x < 2
        puts 1
      else
        puts 2
      end
      TN

    node = body[1].as(NIR::If)
    # `unless C; A; else; B; end` == `if C; B; else; A; end`
    node.then_branch.body.first.as(NIR::Call).args.first.as(NIR::IntLiteral).value.should eq("2")
    expect_present(node.else_branch).body.first.as(NIR::Call).args.first.as(NIR::IntLiteral).value.should eq("1")
  end

  it "normalizes an if modifier into an If with no else branch" do
    body = nir_body(<<-TN)
      x = 5
      puts x if x < 10
      TN

    node = body[1].as(NIR::If)
    node.cond.as(NIR::Call).name.should eq("<")
    node.then_branch.body.first.as(NIR::Call).name.should eq("puts")
    node.else_branch.should be_nil
  end

  it "normalizes an unless modifier into an If with an empty then branch" do
    body = nir_body(<<-TN)
      x = 5
      puts x unless x < 2
      TN

    node = body[1].as(NIR::If)
    node.cond.as(NIR::Call).name.should eq("<")
    node.then_branch.body.should be_empty
    expect_present(node.else_branch).body.first.as(NIR::Call).name.should eq("puts")
  end

  it "translates a while loop" do
    body = nir_body(<<-TN)
      x = 0
      while x < 3
        puts x
      end
      TN

    node = body[1].as(NIR::While)
    node.cond.as(NIR::Call).name.should eq("<")
    node.body.body.first.as(NIR::Call).name.should eq("puts")
  end

  it "translates a checked-add primitive call" do
    body = nir_body("x = 1\nx = x + 1")

    second = body[1].as(NIR::Assign)
    call = second.value.as(NIR::Call)
    call.name.should eq("+")
    expect_present(call.primitive).kind.should eq(NIR::Primitive::Kind::CheckedAdd)
  end

  it "translates integer and Float64 floor operators through shared primitive tags" do
    body = nir_body("puts -7_i8 // 3_i8\nputs 5.5 % -2.0")

    div = body[0].as(NIR::Call).args.first.as(NIR::Call)
    div.type.should eq(Tango::IR::Type.int(:i8))
    expect_present(div.primitive).kind.should eq(NIR::Primitive::Kind::FloorDiv)

    mod = body[1].as(NIR::Call).args.first.as(NIR::Call)
    mod.type.should eq(Tango::IR::Type.float64)
    expect_present(mod.primitive).kind.should eq(NIR::Primitive::Kind::FloorMod)
  end

  it "preserves Int64 literal and checked-add result types" do
    body = nir_body("puts 4_i64 + 5_i64")
    call = body.first.as(NIR::Call).args.first.as(NIR::Call)

    call.type.should eq(Tango::IR::Type.int(:i64))
    expect_present(call.primitive).kind.should eq(NIR::Primitive::Kind::CheckedAdd)
    call.args.map(&.type).should eq([
      Tango::IR::Type.int(:i64),
      Tango::IR::Type.int(:i64),
    ])
  end

  it "preserves Int8 literal and checked-add result types" do
    body = nir_body("puts 4_i8 + 5_i8")
    call = body.first.as(NIR::Call).args.first.as(NIR::Call)

    call.type.should eq(Tango::IR::Type.int(:i8))
    expect_present(call.primitive).kind.should eq(NIR::Primitive::Kind::CheckedAdd)
    call.args.map(&.type).should eq([
      Tango::IR::Type.int(:i8),
      Tango::IR::Type.int(:i8),
    ])
  end

  it "preserves UInt8 literal and checked-add result types" do
    body = nir_body("puts 4_u8 + 5_u8")
    call = body.first.as(NIR::Call).args.first.as(NIR::Call)

    call.type.should eq(Tango::IR::Type.int(:u8))
    expect_present(call.primitive).kind.should eq(NIR::Primitive::Kind::CheckedAdd)
    call.args.map(&.type).should eq([
      Tango::IR::Type.int(:u8),
      Tango::IR::Type.int(:u8),
    ])
  end

  it "preserves Int16 literal and checked-add result types" do
    body = nir_body("puts 4_i16 + 5_i16")
    call = body.first.as(NIR::Call).args.first.as(NIR::Call)

    call.type.should eq(Tango::IR::Type.int(:i16))
    expect_present(call.primitive).kind.should eq(NIR::Primitive::Kind::CheckedAdd)
    call.args.map(&.type).should eq([
      Tango::IR::Type.int(:i16),
      Tango::IR::Type.int(:i16),
    ])
  end

  it "preserves UInt16 literal and checked-add result types" do
    body = nir_body("puts 4_u16 + 5_u16")
    call = body.first.as(NIR::Call).args.first.as(NIR::Call)

    call.type.should eq(Tango::IR::Type.int(:u16))
    expect_present(call.primitive).kind.should eq(NIR::Primitive::Kind::CheckedAdd)
    call.args.map(&.type).should eq([
      Tango::IR::Type.int(:u16),
      Tango::IR::Type.int(:u16),
    ])
  end

  it "preserves UInt64 literal and checked-add result types" do
    body = nir_body("puts 4_u64 + 5_u64")
    call = body.first.as(NIR::Call).args.first.as(NIR::Call)

    call.type.should eq(Tango::IR::Type.int(:u64))
    expect_present(call.primitive).kind.should eq(NIR::Primitive::Kind::CheckedAdd)
    call.args.map(&.type).should eq([
      Tango::IR::Type.int(:u64),
      Tango::IR::Type.int(:u64),
    ])
  end

  it "translates a called def from its typed instance" do
    body = nir_body("def foo(x : Int32) : Int32\n  x\nend\n\nputs foo(1)")

    node = body.first.as(NIR::Def)
    node.name.should eq("foo")
    node.return_type.to_s.should eq("Int32")
    node.body.body.first.should be_a(NIR::Local)
  end

  it "translates called-def params into typed Param nodes" do
    body = nir_body("def foo(x : Int32) : Int32\n  x\nend\n\nputs foo(1)")

    node = body.first.as(NIR::Def)
    node.params.size.should eq(1)
    node.params.first.name.should eq("x")
    node.params.first.type.to_s.should eq("Int32")
    node.params.first.span.should_not be_nil
  end

  it "drops an uncalled def" do
    body = nir_body("def foo(x : Int32) : Int32\n  x\nend")

    body.should be_empty
  end

  it "translates a class" do
    body = nir_body("class Foo\nend")

    node = body.first.as(NIR::Class)
    node.name.should eq("Foo")
    node.superclass_name.should be_nil
    node.fields.should be_empty
  end

  it "records the superclass name" do
    body = nir_body("class Foo\nend\nclass Bar < Foo\nend")

    node = body[1].as(NIR::Class)
    node.name.should eq("Bar")
    node.superclass_name.should eq("Foo")
  end

  it "translates a block-bearing call into Call#block" do
    body = nir_body(<<-TN)
      def each_one
        yield 1
      end
      each_one { |n| puts n }
      TN

    call = body[1].as(NIR::Call)
    call.name.should eq("each_one")
    block = expect_present(call.block)
    block.args.size.should eq(1)
    block.args.first.name.should eq("n")
    block.body.body.first.as(NIR::Call).name.should eq("puts")
  end

  it "turns yield into an invocation of a synthetic typed block parameter" do
    body = nir_body(<<-TN)
      def apply(x : Int32, & : Int32 -> Int32) : Int32
        yield x
      end
      puts apply(20) { |value| value * 2 }
      TN

    definition = body.first.as(NIR::Def)
    block_param = expect_present(definition.block_param)
    block_param.yield_parameter?.should be_true
    block_param.value_required?.should be_true
    block_param.signature.param_types.map(&.to_s).should eq(["Int32"])
    block_param.signature.return_type.to_s.should eq("Int32")

    invocation = definition.body.body.first.as(NIR::InvokeBlock)
    invocation.yield_site?.should be_true
    invocation.receiver.as(NIR::Local).name.should eq(block_param.name)
    invocation.args.first.as(NIR::Local).name.should eq("x")
  end

  it "translates a user-method receiver call into an internal Call" do
    body = nir_body(<<-TN)
      class Box
        def initialize
        end

        def value : Int32
          1
        end
      end
      b = Box.new
      b.value
      TN

    call = body.compact_map(&.as?(NIR::Call)).find { |node| node.name == "value" }
    call.should_not be_nil
    expect_present(call).args.first.as(NIR::Local).name.should eq("b")
  end

  it "recognizes the concurrency primitives as structured nodes" do
    body = nir_body(<<-TN)
      ch = Channel(Int32).new
      spawn { ch.send(1 + 2) }
      puts ch.receive
      TN

    # `Channel(Int32).new` -> ChannelNew keeping the element structurally.
    new = body.compact_map(&.as?(NIR::Assign)).first.value.as(NIR::ChannelNew)
    new.element.should eq(Tango::IR::Type.int(Tango::IR::Type::Width::I32))
    new.capacity.should be_nil

    # `spawn { … }` stays an internal Call carrying the block; its def forwards
    # to a Spawn wrapping the block param.
    spawn_call = expect_present(body.compact_map(&.as?(NIR::Call)).find(&.name.== "spawn"))
    spawn_call.block.should_not be_nil
    spawn_def = expect_present(body.compact_map(&.as?(NIR::Def)).find(&.name.== "spawn"))
    spawn_def.body.body.first.as(NIR::Spawn).proc.as(NIR::Local).name.should eq("block")

    # `ch.send(…)` inside the block -> ChannelOp Send with its value.
    send = expect_present(spawn_call.block).body.body.first.as(NIR::ChannelOp)
    send.kind.should eq(NIR::ChannelOp::Kind::Send)
    send.channel.as(NIR::Local).name.should eq("ch")
    send.value.should_not be_nil

    # `ch.receive` -> ChannelOp Receive, typed as the element.
    receive = expect_present(body.compact_map(&.as?(NIR::Call)).find(&.name.== "puts")).args.first.as(NIR::ChannelOp)
    receive.kind.should eq(NIR::ChannelOp::Kind::Receive)
    receive.type.should eq(Tango::IR::Type.int(Tango::IR::Type::Width::I32))
  end

  it "folds a select expansion into a Select node with per-arm bodies" do
    body = nir_body(<<-TN)
      ch = Channel(Int32).new
      done = Channel(Int32).new
      select
      when x = ch.receive
        puts x
      when done.receive
        puts 0
      end
      TN

    chosen = body.compact_map(&.as?(NIR::Select)).first
    chosen.arms.size.should eq(2)
    chosen.else_body.should be_nil

    # Arm 0: `when x = ch.receive` — a receive that binds `x` (typed as the element).
    receive = chosen.arms[0]
    receive.kind.should eq(NIR::ChannelOp::Kind::Receive)
    receive.channel.as(NIR::Local).name.should eq("ch")
    receive.element.should eq(Tango::IR::Type.int(Tango::IR::Type::Width::I32))
    receive.operation.should be_a(NIR::ChannelOp)
    expect_present(receive.operation.method_site).name.should eq("receive")
    expect_present(receive.captured).name.should eq("x")
    receive.body.body.first.as(NIR::Call).name.should eq("puts")

    # Arm 1: `when done.receive` — a bare receive, no captured local.
    bare = chosen.arms[1]
    bare.channel.as(NIR::Local).name.should eq("done")
    expect_present(bare.operation.method_site).name.should eq("receive")
    bare.captured.should be_nil
  end

  it "folds receive? select actions with a nilable bound local" do
    body = nir_body(<<-TN)
      ch = Channel(Int32).new(1)
      select
      when value = ch.receive?
        if value
          puts value
        end
      end
      TN

    arm = body.compact_map(&.as?(NIR::Select)).first.arms.first
    arm.kind.should eq(NIR::ChannelOp::Kind::ReceiveMaybe)
    arm.element.should eq(Tango::IR::Type.int(:i32))
    expect_present(arm.captured).type.should eq(Tango::IR::Type.int(:i32).with_nil)
  end

  it "recognizes a send arm and a non-blocking else in a select" do
    body = nir_body(<<-TN)
      jobs = Channel(Int32).new(1)
      select
      when jobs.send(1)
        puts 1
      else
        puts 0
      end
      TN

    chosen = body.compact_map(&.as?(NIR::Select)).first
    send = chosen.arms[0]
    send.kind.should eq(NIR::ChannelOp::Kind::Send)
    send.value.should_not be_nil
    send.captured.should be_nil
    # `else` → a non-blocking select carries an else body.
    chosen.else_body.should_not be_nil
  end

  it "recognizes Mutex.new as a MutexNew node and lock/unlock as external calls" do
    body = nir_body(<<-TN)
      mutex = Mutex.new
      mutex.lock
      mutex.unlock
      TN

    # `Mutex.new` -> MutexNew (no structural payload).
    body.compact_map(&.as?(NIR::Assign)).first.value.should be_a(NIR::MutexNew)

    # `mutex.lock`/`mutex.unlock` stay Calls carrying the `@[Go(".Lock")]`
    # binding through to a target (the receiver-vs-package split is downstream).
    lock = expect_present(body.compact_map(&.as?(NIR::Call)).find(&.name.== "lock"))
    lock.targets.any? { |t| t.annotations.any? { |a| a.path == ["Go"] && a.string_args.includes?(".Lock") } }.should be_true
    lock.args.first.as(NIR::Local).name.should eq("mutex")
  end

  # Crystal's semantic phase normalizes multi-assign into plain assigns
  # (through temp locals) before ToNIR sees the tree, so it arrives as
  # supported Assign nodes with spans rather than an UnsupportedExpr.
  it "translates a normalized multi-assign into plain assigns with spans" do
    body = nir_body("a, b = 1, 2")

    assigns = body.map(&.as(NIR::Assign))
    target_names = assigns.map(&.target.as(NIR::Local).name)
    target_names.should contain("a")
    target_names.should contain("b")
    assigns.each { |assign| assign.span.should_not be_nil }
  end
end
