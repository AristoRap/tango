require "../spec_helper"

private def lir_for(source : String) : Tango::IR::LIR::Program
  expect_present(Tango.snapshot(source, filename: "probe.tn").lir)
end

describe Tango::Lowering::ToLIR do
  it "commits scalar-system intrinsics, powers, and checked float conversion" do
    program = lir_for("x = 0.0\ni = 1_i8\nputs(-x)\nputs(-i)\nputs(2.0 ** 3)\nputs(1.0.to_i8)\nputs(2_i8 ** 3_u16)")
    values = program.body.compact_map(&.as?(Tango::IR::LIR::ExternalCall)).map(&.args.first)

    values[0].as(Tango::IR::LIR::FloatIntrinsic).operation.negate?.should be_true
    values[1].should be_a(Tango::IR::LIR::IntegerNegate)
    values[2].as(Tango::IR::LIR::FloatArithmetic).operation.pow_integer?.should be_true
    values[3].should be_a(Tango::IR::LIR::FloatToIntegerConvert)
    values[4].as(Tango::IR::LIR::IntegerOperationValue).kind.pow?.should be_true
  end

  it "commits integer operations, conversions, parsing, and Char#ord explicitly" do
    program = lir_for("puts(1_u64 &+ 2_u64)\nputs(~3_i16)\nputs(4_u8 << 2_i64)\nputs(5_i32.to_u8!)\nputs(\"6\".to_u16)\nputs(\"A\"[0].ord)")
    values = program.body.compact_map(&.as?(Tango::IR::LIR::ExternalCall)).map(&.args.first)

    values[0].as(Tango::IR::LIR::IntegerOperationValue).kind.wrapping_add?.should be_true
    values[1].should be_a(Tango::IR::LIR::IntegerBitNot)
    values[2].as(Tango::IR::LIR::IntegerOperationValue).kind.shift_left?.should be_true
    values[3].as(Tango::IR::LIR::IntegerConvert).mode.wrapping?.should be_true
    program.functions.flat_map(&.body).any? { |stmt| Tango::IR::LIR::Walk.children(stmt).any?(&.is_a?(Tango::IR::LIR::StringToInteger)) }.should be_true
    values[5].as(Tango::IR::LIR::NumericConvert).source.family.char?.should be_true
  end

  it "commits report comparison, conversion, and rounding as typed values" do
    program = lir_for("puts(\"Berlin\" <=> \"Amsterdam\")\nputs 3.to_f\nputs 11.5.round")
    values = program.body.map(&.as(Tango::IR::LIR::ExternalCall)).map(&.args.first)

    values[0].should be_a(Tango::IR::LIR::StringCompare)
    conversion = values[1].as(Tango::IR::LIR::NumericConvert)
    conversion.source.should eq(Tango::IR::Type.int(:i32))
    conversion.target.should eq(Tango::IR::Type.float64)
    rounding = values[2].as(Tango::IR::LIR::FloatIntrinsic)
    rounding.operation.round_even?.should be_true
  end

  it "commits Float64 ordering to target-neutral binary LIR" do
    program = lir_for("puts(1.0 < 2.0)\nputs(3.0 > 4.0)")
    comparisons = program.body.map(&.as(Tango::IR::LIR::ExternalCall)).map { |call| call.args.first.as(Tango::IR::LIR::Binary) }

    comparisons.map(&.operator).should eq(["<", ">"])
    comparisons.each do |comparison|
      comparison.left.should be_a(Tango::IR::LIR::FloatConst)
      comparison.right.should be_a(Tango::IR::LIR::FloatConst)
    end
  end

  it "commits decimal parsing as a typed LIR operation" do
    program = lir_for("puts \"12.5\".to_f")

    output = program.body.compact_map(&.as?(Tango::IR::LIR::ExternalCall)).first
    parse = output.args.first.as(Tango::IR::LIR::StringToFloat)
    parse.string.as(Tango::IR::LIR::StringConst).value.should eq("12.5")
  end

  it "normalizes statically known Crystal truthiness to Bool conditions" do
    program = expect_present(Tango.pre_target_snapshot("if 1\n  puts 1\nend\nif nil\n  puts 2\nend").lir)

    first = program.body[0].as(Tango::IR::LIR::If)
    second = program.body[1].as(Tango::IR::LIR::If)
    first.cond.as(Tango::IR::LIR::BoolConst).value.should be_true
    second.cond.as(Tango::IR::LIR::BoolConst).value.should be_false
  end

  it "emits one function for repeated uses of the same yield specialization" do
    source = <<-TN
      1.times { |i| puts i }
      2.times { |i| puts i }
      TN
    program = expect_present(Tango.pre_target_snapshot(source).lir)

    times = program.functions.select(&.name.starts_with?("times_"))
    times.size.should eq(1)
  end

  it "commits field defaults between allocation and explicit initialization" do
    program = lir_for(<<-TN)
      class Settings
        property count : Int32 = 2

        def initialize
          @count = 3
        end
      end

      settings = Settings.new
      puts settings.count
      TN

    constructor = program.functions.find { |function| function.name == "Settings__new" }
    constructor.should_not be_nil
    body = expect_present(constructor).body
    body[0].should be_a(Tango::IR::LIR::Assign)
    default = body[1].as(Tango::IR::LIR::FieldAssign)
    default.field.should eq("count")
    default.value.as(Tango::IR::LIR::IntConst).value.should eq("2")
    body[2].as(Tango::IR::LIR::Discard).value.as(Tango::IR::LIR::Call).name.should start_with("initialize")
  end

  it "commits an autocast numeric constructor literal through the resolved initializer" do
    program = lir_for(<<-TN)
      class StationStats
        getter sum : Float64

        def initialize(measurement : Float64)
          @sum = measurement
        end
      end

      stats = StationStats.new(10)
      puts stats.sum
      TN

    assignment = program.body.compact_map(&.as?(Tango::IR::LIR::Assign)).first
    call = assignment.value.as(Tango::IR::LIR::Call)
    call.name.should eq("StationStats__new_Float64")
    call.args.first.as(Tango::IR::LIR::FloatConst).value.should eq("10")
    program.functions.map(&.name).should contain("initialize_StationStats_Float64")
  end

  it "lowers a handler and raise through structured abrupt-flow nodes" do
    program = lir_for(<<-TN)
      begin
        raise "boom"
      rescue ex
        puts ex.message
      ensure
        puts "done"
      end
      TN

    handler = program.body.first.as(Tango::IR::LIR::Handler)
    raised = handler.body.first.as(Tango::IR::LIR::AbruptExit)
    raised.shape.should eq(Tango::IR::LIR::AbruptExit::Shape::RaiseMessage)
    handler.clauses.first.should be_a(Tango::IR::LIR::RescueClause(Array(Tango::IR::LIR::Stmt)))
    handler.clauses.first.binding.should eq("ex")
    handler.ensure_body.should_not be_nil
  end

  it "declares a local on first assignment" do
    program = lir_for("x = 1\nputs x")

    assign = program.body.first.as(Tango::IR::LIR::Assign)
    assign.target.should eq("x")
    assign.mode.should eq(Tango::IR::LIR::Assign::Mode::Declare)
    assign.value.as(Tango::IR::LIR::IntConst).value.should eq("1")
    assign.loc.should eq(Tango::IR::LIR::SourceLoc.new("probe.tn", 1, 1))
  end

  it "reassigns a local on a later assignment to the same name" do
    program = lir_for("x = 1\nx = 2\nputs x")

    first = program.body[0].as(Tango::IR::LIR::Assign)
    second = program.body[1].as(Tango::IR::LIR::Assign)

    first.mode.should eq(Tango::IR::LIR::Assign::Mode::Declare)
    second.mode.should eq(Tango::IR::LIR::Assign::Mode::Reassign)
  end

  it "lowers a local read into a Temp value" do
    program = lir_for("x = 1\nputs x")

    call = program.body[1].as(Tango::IR::LIR::ExternalCall)
    call.args.first.as(Tango::IR::LIR::Temp).name.should eq("x")
  end

  it "discards a bare local or literal statement" do
    program = lir_for("x = 1\nx")

    discard = program.body[1].as(Tango::IR::LIR::Discard)
    discard.value.as(Tango::IR::LIR::Temp).name.should eq("x")
  end

  it "lowers statement-position if into structured LIR" do
    source = <<-TN
      x = 1
      if true
        puts x
      else
        puts 2
      end
      TN

    program = lir_for(source)

    program.body[0].should be_a(Tango::IR::LIR::Assign)
    node = program.body[1].as(Tango::IR::LIR::If)
    node.cond.as(Tango::IR::LIR::BoolConst).value.should be_true
    node.then_body.first.should be_a(Tango::IR::LIR::ExternalCall)
    node.else_body.first.should be_a(Tango::IR::LIR::ExternalCall)
  end

  it "lowers a while loop into structured LIR::While" do
    source = <<-TN
      x = 0
      while x < 3
        puts x
      end
      TN

    program = lir_for(source)

    program.body[0].should be_a(Tango::IR::LIR::Assign)
    node = program.body[1].as(Tango::IR::LIR::While)
    node.cond.should be_a(Tango::IR::LIR::Binary)
    node.body.first.should be_a(Tango::IR::LIR::ExternalCall)
  end

  it "lowers a checked-add primitive call into LIR::CheckedArithmetic" do
    program = lir_for("x = 1\nx = x + 1")

    second = program.body[1].as(Tango::IR::LIR::Assign)
    value = second.value.as(Tango::IR::LIR::CheckedArithmetic)
    value.operation.should eq(Tango::IR::LIR::CheckedOperation::Add)
    value.left.as(Tango::IR::LIR::Temp).name.should eq("x")
    value.right.as(Tango::IR::LIR::IntConst).value.should eq("1")
  end

  it "lowers integer and Float64 floor operators through one LIR owner" do
    program = lir_for("puts -7_i16 // 3_i16\nputs 5.5 % -2.0")

    div = program.body[0].as(Tango::IR::LIR::ExternalCall).args.first.as(Tango::IR::LIR::FloorArithmetic)
    div.operation.should eq(Tango::IR::LIR::FloorOperation::Div)
    div.type.should eq(Tango::IR::Type.int(:i16))

    mod = program.body[1].as(Tango::IR::LIR::ExternalCall).args.first.as(Tango::IR::LIR::FloorArithmetic)
    mod.operation.should eq(Tango::IR::LIR::FloorOperation::Mod)
    mod.type.should eq(Tango::IR::Type.float64)
  end

  it "carries Int64 through literals and checked addition" do
    program = lir_for("x = 4_i64\nx = x + 5_i64")

    first = program.body[0].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::IntConst)
    first.type.should eq(Tango::IR::Type.int(:i64))

    add = program.body[1].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::CheckedArithmetic)
    add.type.should eq(Tango::IR::Type.int(:i64))
    add.right.as(Tango::IR::LIR::IntConst).type.should eq(Tango::IR::Type.int(:i64))
  end

  it "carries Int8 through literals and checked addition" do
    program = lir_for("x = 4_i8\nx = x + 5_i8")

    first = program.body[0].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::IntConst)
    first.type.should eq(Tango::IR::Type.int(:i8))

    add = program.body[1].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::CheckedArithmetic)
    add.type.should eq(Tango::IR::Type.int(:i8))
    add.right.as(Tango::IR::LIR::IntConst).type.should eq(Tango::IR::Type.int(:i8))
  end

  it "carries UInt8 through literals and checked addition" do
    program = lir_for("x = 4_u8\nx = x + 5_u8")

    first = program.body[0].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::IntConst)
    first.type.should eq(Tango::IR::Type.int(:u8))

    add = program.body[1].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::CheckedArithmetic)
    add.type.should eq(Tango::IR::Type.int(:u8))
    add.right.as(Tango::IR::LIR::IntConst).type.should eq(Tango::IR::Type.int(:u8))
  end

  it "carries Int16 through literals and checked addition" do
    program = lir_for("x = 4_i16\nx = x + 5_i16")

    first = program.body[0].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::IntConst)
    first.type.should eq(Tango::IR::Type.int(:i16))

    add = program.body[1].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::CheckedArithmetic)
    add.type.should eq(Tango::IR::Type.int(:i16))
    add.right.as(Tango::IR::LIR::IntConst).type.should eq(Tango::IR::Type.int(:i16))
  end

  it "carries UInt16 through literals and checked addition" do
    program = lir_for("x = 4_u16\nx = x + 5_u16")

    first = program.body[0].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::IntConst)
    first.type.should eq(Tango::IR::Type.int(:u16))

    add = program.body[1].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::CheckedArithmetic)
    add.type.should eq(Tango::IR::Type.int(:u16))
    add.right.as(Tango::IR::LIR::IntConst).type.should eq(Tango::IR::Type.int(:u16))
  end

  it "carries UInt64 through literals and checked addition" do
    program = lir_for("x = 4_u64\nx = x + 5_u64")

    first = program.body[0].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::IntConst)
    first.type.should eq(Tango::IR::Type.int(:u64))

    add = program.body[1].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::CheckedArithmetic)
    add.type.should eq(Tango::IR::Type.int(:u64))
    add.right.as(Tango::IR::LIR::IntConst).type.should eq(Tango::IR::Type.int(:u64))
  end

  it "lowers a called def into a Func with a tail-position Return" do
    program = lir_for("def add(a : Int32, b : Int32) : Int32\n  a + b\nend\n\nputs add(1, 2)")

    func = program.functions.first
    # The monomorphized Go function name carries the concrete signature.
    func.name.should eq("add_Int32_Int32")
    func.return_type.to_s.should eq("Int32")
    func.params.map(&.name).should eq(["a", "b"])
    func.params.map { |param| param.type.to_s }.should eq(["Int32", "Int32"])

    ret = func.body.first.as(Tango::IR::LIR::AbruptExit)
    ret.shape.should eq(Tango::IR::LIR::AbruptExit::Shape::Return)
    func.loc.should eq(Tango::IR::LIR::SourceLoc.new("probe.tn", 1, 1))
    ret.loc.should eq(Tango::IR::LIR::SourceLoc.new("probe.tn", 2, 3))
    add = ret.value.as(Tango::IR::LIR::CheckedArithmetic)
    add.left.as(Tango::IR::LIR::Temp).name.should eq("a")
    add.right.as(Tango::IR::LIR::Temp).name.should eq("b")
  end

  it "lowers an internal call in argument position into LIR::Call" do
    program = lir_for("def add(a : Int32, b : Int32) : Int32\n  a + b\nend\n\nputs add(1, 2)")

    outer = program.body.first.as(Tango::IR::LIR::ExternalCall)
    call = outer.args.first.as(Tango::IR::LIR::Call)
    # The call site routes to the same monomorphized name as the definition.
    call.name.should eq("add_Int32_Int32")
    call.args.map(&.as(Tango::IR::LIR::IntConst).value).should eq(["1", "2"])
  end

  it "lowers value-position if into IfValue" do
    source = <<-TN
      x = if true
        1
      else
        2
      end
      puts x
      TN

    program = lir_for(source)

    assign = program.body.first.as(Tango::IR::LIR::Assign)
    value = assign.value.as(Tango::IR::LIR::IfValue)
    value.cond.as(Tango::IR::LIR::BoolConst).value.should be_true
    value.then_value.as(Tango::IR::LIR::IntConst).value.should eq("1")
    value.else_value.as(Tango::IR::LIR::IntConst).value.should eq("2")
  end

  it "lowers carrier widening to a named conversion declaration and Widen value" do
    program = lir_for(<<-TN)
      def choose(number : Bool) : Int32 | String
        number ? 7 : "seven"
      end

      def widen(number : Bool, absent : Bool) : Int32 | String | Nil
        absent ? nil : choose(number)
      end

      value = widen(true, false)
      TN

    conversion = program.conversions.first
    conversion.mapping.variants.map { |variant| {variant.source_tag, variant.target_tag} }.should eq([{0, 1}, {1, 2}])

    function = expect_present(program.functions.find(&.name.starts_with?("widen_")))
    result = function.body.first.as(Tango::IR::LIR::AbruptExit).value.as(Tango::IR::LIR::IfValue)
    widened = result.else_value.as(Tango::IR::LIR::Widen)
    widened.conversion.should eq(conversion.mapping.name)
    widened.source.to_s.should eq("Int32 | String")
    widened.union.to_s.should eq("Int32 | String | Nil")
  end

  it "lowers `.nil?` on a carrier union to a CarrierNil type test" do
    program = lir_for(<<-TN)
      def maybe(hit : Bool) : Int32?
        hit ? 5 : nil
      end

      present = maybe(true).nil?
      puts present
      TN

    test = program.body[-2].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::TypeTest)
    test.strategy.should eq(Tango::IR::LIR::TypeTest::Strategy::CarrierNil)
    test.source.to_s.should eq("Int32?")
    test.target.nil_type?.should be_true
  end

  it "lowers a bare `nil` into a `Nil` slot as the standalone NilValue unit" do
    program = lir_for(<<-TN)
      def describe(value : Nil) : String
        "absent"
      end

      describe(nil)
      TN

    call = program.body.last.as(Tango::IR::LIR::Discard).value.as(Tango::IR::LIR::Call)
    # A `Nil`-typed slot is neither the pointer arm's Go nil (NilConst) nor a
    # carrier box — it is the zero-size unit value.
    call.args.first.should be_a(Tango::IR::LIR::NilValue)
  end

  it "lowers value-position rescue into typed result arms" do
    program = lir_for(<<-TN)
      x = begin
        raise "boom" if true
        1
      rescue
        2
      end
      puts x
      TN

    value = program.body.first.as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::RescueValue)
    value.type.should eq(Tango::IR::Type.int(:i32))
    value.clauses.first.should be_a(Tango::IR::LIR::RescueClause(Tango::IR::LIR::RescueValue::Arm))
    value.body.body.first.as(Tango::IR::LIR::If).then_body.first.as(Tango::IR::LIR::AbruptExit).shape.should eq(Tango::IR::LIR::AbruptExit::Shape::RaiseMessage)
    value.body.value.as(Tango::IR::LIR::IntConst).value.should eq("1")
    value.clauses.first.body.value.as(Tango::IR::LIR::IntConst).value.should eq("2")
  end

  it "lowers channel new/send/receive and spawn to their LIR shapes" do
    program = lir_for(<<-TN)
      ch = Channel(Int32).new
      spawn { ch.send(1 + 2) }
      puts ch.receive
      TN

    # `ch = Channel(Int32).new` -> MakeChan keyed by the element.
    make = program.body.first.as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::MakeChan)
    make.element.should eq(Tango::IR::Type.int(Tango::IR::Type::Width::I32))

    # `spawn`'s func body is a Spawn over the block param.
    spawn_func = expect_present(program.functions.find(&.name.starts_with?("spawn")))
    spawn_func.body.first.as(Tango::IR::LIR::Spawn).proc.as(Tango::IR::LIR::Temp).name.should eq("block")

    # The spawned closure sends into the channel.
    closure = program.body[1].as(Tango::IR::LIR::Discard).value.as(Tango::IR::LIR::Call).args.first.as(Tango::IR::LIR::Closure)
    closure.body.first.should be_a(Tango::IR::LIR::ChanSend)

    # `puts ch.receive` -> a checked ChanReceive argument.
    receive = program.body[2].as(Tango::IR::LIR::ExternalCall).args.first.as(Tango::IR::LIR::ChanReceive)
    receive.element.should eq(Tango::IR::Type.int(Tango::IR::Type::Width::I32))
  end

  it "lowers new(capacity)/close/reference-element receive? to their LIR shapes" do
    program = lir_for(<<-TN)
      class Signal
      end
      ch = Channel(Signal).new(1)
      ch.close
      got = ch.receive?
      got
      TN

    make = program.body.first.as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::MakeChan)
    make.capacity.as(Tango::IR::LIR::IntConst).value.should eq("1")
    program.body[1].should be_a(Tango::IR::LIR::ChanClose)
    # A reference element rides the pointer arm: a raw ChanReceiveMaybe, no carrier.
    program.body[2].as(Tango::IR::LIR::Assign).value.should be_a(Tango::IR::LIR::ChanReceiveMaybe)
  end

  it "lowers receive? on a value element to the planned carrier protocol" do
    program = lir_for(<<-TN)
      ch = Channel(Int32).new
      got = ch.receive?
      got
      TN

    value = program.body[1].as(Tango::IR::LIR::Assign).value.as(Tango::IR::LIR::ChanReceiveMaybeBox)
    value.element.should eq(Tango::IR::Type.int(:i32))
    value.union.should eq(Tango::IR::Type.int(:i32).with_nil)
  end

  it "does not reconstruct receive? representation when its plan is missing" do
    element = Tango::IR::Type.klass("Signal")
    channel_type = Tango::IR::Type.klass("Channel", [element])
    result_type = element.with_nil
    channel = Tango::IR::NIR::Local.new(Tango::NodeId.new("channel"), "ch", channel_type, nil)
    receive = Tango::IR::NIR::ChannelOp.new(
      Tango::NodeId.new("receive"),
      Tango::IR::NIR::ChannelOp::Kind::ReceiveMaybe,
      channel,
      nil,
      element,
      result_type,
      nil
    )
    program = Tango::IR::NIR::Program.new([receive] of Tango::IR::NIR::Stmt)
    plans = Tango::Planning::Plans::Table.new
    plans.uncaught_exception = Tango::IR::UncaughtExceptionStrategy::CrystalStyle

    lir = Tango::Lowering::ToLIR.translate(program, Tango::Analysis::Facts::Table.new, plans)

    value = lir.body.first.as(Tango::IR::LIR::Discard).value.as(Tango::IR::LIR::UnsupportedValue)
    value.reason.should contain("unplanned receive? representation")
  end

  it "lowers a select into LIR::Select with per-arm receive comm clauses" do
    program = lir_for(<<-TN)
      ch = Channel(Int32).new
      done = Channel(Int32).new
      select
      when x = ch.receive
        puts x
      when done.receive
        puts 0
      end
      TN

    chosen = program.body.compact_map(&.as?(Tango::IR::LIR::Select)).first
    chosen.arms.size.should eq(2)
    chosen.default.should be_nil

    chosen.arms[0].kind.should eq(Tango::IR::LIR::Select::Arm::Kind::Receive)
    chosen.arms[0].binding.should eq("x")
    chosen.arms[0].channel.as(Tango::IR::LIR::Temp).name.should eq("ch")
    chosen.arms[0].body.first.should be_a(Tango::IR::LIR::ExternalCall)

    # The bare-receive arm has no binding.
    chosen.arms[1].binding.should be_nil
    chosen.arms[1].channel.as(Tango::IR::LIR::Temp).name.should eq("done")
  end

  it "commits carrier receive? and drops an unread select binding" do
    program = lir_for(<<-TN)
      values = Channel(Int32).new(1)
      values.send(9)
      select
      when item = values.receive?
        if item
          puts item
        end
      end

      ignored = Channel(Int32).new(1)
      ignored.send(1)
      select
      when unread = ignored.receive
        puts 2
      end
      TN

    selects = program.body.compact_map(&.as?(Tango::IR::LIR::Select))
    maybe = selects[0].arms.first
    maybe.kind.should eq(Tango::IR::LIR::Select::Arm::Kind::ReceiveMaybeCarrier)
    maybe.binding.should eq("item")
    maybe.result_type.should eq(Tango::IR::Type.int(:i32).with_nil)
    maybe.body.first.as(Tango::IR::LIR::If).then_body.first.as(Tango::IR::LIR::ExternalCall).args.first.should be_a(Tango::IR::LIR::Unbox)

    unread = selects[1].arms.first
    unread.kind.should eq(Tango::IR::LIR::Select::Arm::Kind::Receive)
    unread.binding.should be_nil
  end

  it "lowers Mutex.new to MakeMutex and lock/unlock to receiver-method external calls" do
    program = lir_for(<<-TN)
      mutex = Mutex.new
      mutex.lock
      mutex.unlock
      TN

    # `Mutex.new` -> MakeMutex (no structural payload).
    program.body.first.as(Tango::IR::LIR::Assign).value.should be_a(Tango::IR::LIR::MakeMutex)

    # `mutex.lock` -> an ExternalCall whose target is the Go-method binding
    # form: receiver_method true, name "Lock" (dot stripped), no package.
    lock = program.body[1].as(Tango::IR::LIR::ExternalCall)
    lock.target.receiver_method?.should be_true
    lock.target.name.should eq("Lock")
    lock.target.package_name.should be_nil
    lock.args.first.as(Tango::IR::LIR::Temp).name.should eq("mutex")
  end
end
