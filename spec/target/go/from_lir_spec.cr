require "../../spec_helper"

private def go_channel_type(type : Tango::IR::Type) : Tango::IR::ExternalType
  Tango::IR::ExternalType.new(
    type,
    Tango::IR::ExternalBinding.new("go"),
    Tango::IR::ExternalType::Shape::NativeChannel
  )
end

private def go_mutex_type(type : Tango::IR::Type) : Tango::IR::ExternalType
  Tango::IR::ExternalType.new(
    type,
    Tango::IR::ExternalBinding.qualified("go", "sync.Mutex"),
    Tango::IR::ExternalType::Shape::NamedPointer
  )
end

describe Tango::Target::Go::FromLIR do
  it "fails loud when an unsupported value reaches target translation" do
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Discard.new(Tango::IR::LIR::UnsupportedValue.new("missing lowering")),
    ] of Tango::IR::LIR::Stmt)

    expect_raises(ArgumentError, "unsupported LIR value: missing lowering") do
      Tango::Target::Go::FromLIR.translate(program)
    end
  end

  it "emits both numeric sleep calls through one imported runtime helper" do
    target = Tango::IR::LIR::ExternalTarget.new("go", nil, "tangoSleep")
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::ExternalCall.new(target, [Tango::IR::LIR::IntConst.new("0")] of Tango::IR::LIR::Value),
      Tango::IR::LIR::ExternalCall.new(target, [Tango::IR::LIR::FloatConst.new("0.0")] of Tango::IR::LIR::Value),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.scan(/func tangoSleep/).size.should eq(1)
    source.should contain(%(import "time"))
    source.should contain("time.Sleep(time.Duration(float64(seconds) * float64(time.Second)))")
    source.should contain("tangoSleep(int32(0))")
    source.should contain("tangoSleep(float64(0.0))")
  end

  it "emits handler IIFEs with ensure-before-recover defer order and typed panic filtering" do
    message = Tango::IR::LIR::ExternalTarget.new("go", nil, "tangoMessage", true)
    handler = Tango::IR::LIR::Handler.new(
      [Tango::IR::LIR::AbruptExit.new(Tango::IR::LIR::AbruptExit::Shape::RaiseMessage, Tango::IR::LIR::StringConst.new("boom"))] of Tango::IR::LIR::Stmt,
      [Tango::IR::LIR::RescueClause(Array(Tango::IR::LIR::Stmt)).new(
        [] of Tango::IR::Type,
        "ex",
        [Tango::IR::LIR::ExternalCall.new(message, [Tango::IR::LIR::Temp.new("ex")] of Tango::IR::LIR::Value)] of Tango::IR::LIR::Stmt,
        true
      )] of Tango::IR::LIR::RescueClause(Array(Tango::IR::LIR::Stmt)),
      nil,
      [Tango::IR::LIR::Discard.new(Tango::IR::LIR::StringConst.new("ensured"))] of Tango::IR::LIR::Stmt
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(Tango::IR::LIR::Program.new([handler] of Tango::IR::LIR::Stmt)))

    ensure_at = expect_present(source.index(%(_ = "ensured")))
    # The entrypoint translator owns an earlier `recover`; this assertion is
    # about the handler IIFE's existing ensure-before-recover order.
    recover_at = expect_present(source.rindex("recover()"))
    ensure_at.should be < recover_at
    source.should contain(".(tangoException)")
    source.should contain(%(panic(&tangoExceptionValue{message: "boom"})))
  end

  it "emits value handlers through a typed result slot" do
    value = Tango::IR::LIR::RescueValue.new(
      Tango::IR::LIR::RescueValue::Arm.new(
        [Tango::IR::LIR::AbruptExit.new(Tango::IR::LIR::AbruptExit::Shape::RaiseMessage, Tango::IR::LIR::StringConst.new("boom"))] of Tango::IR::LIR::Stmt,
        Tango::IR::LIR::IntConst.new("1")
      ),
      [Tango::IR::LIR::RescueClause(Tango::IR::LIR::RescueValue::Arm).new(
        [] of Tango::IR::Type,
        nil,
        Tango::IR::LIR::RescueValue::Arm.new([] of Tango::IR::LIR::Stmt, Tango::IR::LIR::IntConst.new("2")),
        true
      )],
      nil,
      nil,
      Tango::IR::Type.int(:i32)
    )
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new("x", value, Tango::IR::LIR::Assign::Mode::Declare),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("var x int32")
    source.should contain("x = int32(1)")
    source.should contain("x = int32(2)")
    source.should contain("recover()")
  end

  it "emits typed runtime methods for a planned user exception" do
    type = Tango::IR::LIR::StructType.new(
      "SubError",
      [Tango::IR::Field.new("message", Tango::IR::Type.string)],
      true,
      ["SubError", "BaseError", "Exception"]
    )
    source = Tango::Target::Go::Source.emit(
      Tango::Target::Go::FromLIR.translate(Tango::IR::LIR::Program.new(
        [] of Tango::IR::LIR::Stmt,
        types: [type]
      ))
    )

    source.should contain("func (e *SubError) tangoExceptionMarker()")
    source.should contain("func (e *SubError) tangoMessage() string")
    source.should contain("func (e *SubError) Error() string")
    source.should contain(%(return name == "SubError" || name == "BaseError" || name == "Exception"))
  end

  it "dispatches typed rescue through the exception subtype predicate" do
    handler = Tango::IR::LIR::Handler.new(
      [Tango::IR::LIR::AbruptExit.new(Tango::IR::LIR::AbruptExit::Shape::RaiseMessage, Tango::IR::LIR::StringConst.new("boom"))] of Tango::IR::LIR::Stmt,
      [Tango::IR::LIR::RescueClause(Array(Tango::IR::LIR::Stmt)).new(
        [Tango::IR::Type.klass("BaseError")],
        nil,
        [] of Tango::IR::LIR::Stmt,
        false
      )],
      nil,
      nil
    )
    source = Tango::Target::Go::Source.emit(
      Tango::Target::Go::FromLIR.translate(Tango::IR::LIR::Program.new([handler] of Tango::IR::LIR::Stmt))
    )

    source.should contain(%(.tangoIsA("BaseError")))
  end

  it "emits declare, reassign, and discard statements as Go text" do
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new("x", Tango::IR::LIR::IntConst.new("1"), Tango::IR::LIR::Assign::Mode::Declare),
      Tango::IR::LIR::Assign.new("x", Tango::IR::LIR::IntConst.new("2"), Tango::IR::LIR::Assign::Mode::Reassign),
      Tango::IR::LIR::Discard.new(Tango::IR::LIR::Temp.new("x")),
    ] of Tango::IR::LIR::Stmt)

    file = Tango::Target::Go::FromLIR.translate(program)
    source = Tango::Target::Go::Source.emit(file)

    source.should contain("x := int32(1)")
    source.should contain("x = int32(2)")
    source.should contain("_ = x")
  end

  it "emits a standalone `Nil` as the zero-size tangoNil type and unit value" do
    program = Tango::IR::LIR::Program.new(
      [Tango::IR::LIR::Assign.new("value", Tango::IR::LIR::NilValue.new, Tango::IR::LIR::Assign::Mode::Declare)] of Tango::IR::LIR::Stmt,
      [
        Tango::IR::LIR::Func.new(
          "describe",
          [Tango::IR::LIR::Param.new("value", Tango::IR::Type::NIL)],
          Tango::IR::Type.string,
          [Tango::IR::LIR::AbruptExit.new(Tango::IR::LIR::AbruptExit::Shape::Return, Tango::IR::LIR::StringConst.new("absent"))] of Tango::IR::LIR::Stmt
        ),
      ] of Tango::IR::LIR::Func
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    # The runtime type decl, the Nil-typed parameter, and the unit value — none
    # of them Go `nil` (NilConst) or a carrier box.
    source.should contain("type tangoNil struct{}")
    source.should contain("value tangoNil")
    source.should contain("value := tangoNil{}")
  end

  it "emits Go line directives for functions and source-backed statements" do
    program = Tango::IR::LIR::Program.new(
      [
        Tango::IR::LIR::Assign.new(
          "x",
          Tango::IR::LIR::IntConst.new("1"),
          Tango::IR::LIR::Assign::Mode::Declare,
          Tango::IR::LIR::SourceLoc.new("main.tn", 5, 3)
        ),
      ] of Tango::IR::LIR::Stmt,
      [
        Tango::IR::LIR::Func.new(
          "answer",
          [] of Tango::IR::LIR::Param,
          Tango::IR::Type.int(:i32),
          [
            Tango::IR::LIR::AbruptExit.new(
              Tango::IR::LIR::AbruptExit::Shape::Return,
              Tango::IR::LIR::IntConst.new("42"),
              Tango::IR::LIR::SourceLoc.new("defs.tn", 2, 3)
            ),
          ] of Tango::IR::LIR::Stmt,
          Tango::IR::LIR::SourceLoc.new("defs.tn", 1, 1)
        ),
      ] of Tango::IR::LIR::Func
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("//line defs.tn:1:1\nfunc answer() int32 {")
    source.should contain("//line defs.tn:2:3\n\treturn int32(42)")
    source.should contain("//line main.tn:5:3\n\tx := int32(1)")
  end

  it "emits a while loop as a Go for statement" do
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::While.new(
        Tango::IR::LIR::BoolConst.new(true),
        [Tango::IR::LIR::Discard.new(Tango::IR::LIR::IntConst.new("1"))] of Tango::IR::LIR::Stmt
      ),
    ] of Tango::IR::LIR::Stmt)

    file = Tango::Target::Go::FromLIR.translate(program)
    source = Tango::Target::Go::Source.emit(file)

    source.should contain("for {")
    source.should contain("_ = int32(1)")
  end

  it "emits a Func with params, a return type, and a Return statement" do
    program = Tango::IR::LIR::Program.new(
      [] of Tango::IR::LIR::Stmt,
      [Tango::IR::LIR::Func.new(
        "add",
        [Tango::IR::LIR::Param.new("a", Tango::IR::Type.int(:i32)), Tango::IR::LIR::Param.new("b", Tango::IR::Type.int(:i32))],
        Tango::IR::Type.int(:i32),
        [Tango::IR::LIR::AbruptExit.new(Tango::IR::LIR::AbruptExit::Shape::Return, Tango::IR::LIR::Temp.new("a"))] of Tango::IR::LIR::Stmt
      )]
    )

    file = Tango::Target::Go::FromLIR.translate(program)
    source = Tango::Target::Go::Source.emit(file)

    source.should contain("func add(a int32, b int32) int32 {")
    source.should contain("return a")
  end

  it "emits an internal call as a plain Go call" do
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Discard.new(
        Tango::IR::LIR::Call.new("add", [Tango::IR::LIR::IntConst.new("1"), Tango::IR::LIR::IntConst.new("2")] of Tango::IR::LIR::Value)
      ),
    ] of Tango::IR::LIR::Stmt)

    file = Tango::Target::Go::FromLIR.translate(program)
    source = Tango::Target::Go::Source.emit(file)

    # A discarded call is a bare statement: valid Go for any return arity,
    # and the only legal spelling when the call returns nothing.
    source.should contain("add(int32(1), int32(2))")
    source.should_not contain("_ = add")
  end

  it "emits a checked-add call for a CheckedArithmetic value and registers its helper" do
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new(
        "x",
        Tango::IR::LIR::CheckedArithmetic.new(
          Tango::IR::LIR::CheckedOperation::Add,
          Tango::IR::LIR::Temp.new("x"),
          Tango::IR::LIR::IntConst.new("1"),
          Tango::IR::Type.int(:i32),
          Tango::IR::CheckedArithmeticStrategy::WideningRoundTrip
        ),
        Tango::IR::LIR::Assign::Mode::Reassign
      ),
    ] of Tango::IR::LIR::Stmt)

    file = Tango::Target::Go::FromLIR.translate(program)
    source = Tango::Target::Go::Source.emit(file)

    source.should contain("x = tangoAddI32(x, int32(1))")
    source.should contain("func tangoAddI32(")
  end

  it "emits Int64 literals and width-general checked addition" do
    i64 = Tango::IR::Type.int(:i64)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new(
        "x",
        Tango::IR::LIR::CheckedArithmetic.new(
          Tango::IR::LIR::CheckedOperation::Add,
          Tango::IR::LIR::IntConst.new("9223372036854775807", i64),
          Tango::IR::LIR::IntConst.new("1", i64),
          i64,
          Tango::IR::CheckedArithmeticStrategy::SignedSameWidth
        ),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("x := tangoAddI64(int64(9223372036854775807), int64(1))")
    source.should contain("if (c < a) != (b < 0) {")
    source.should_not contain("int64(int64(c))")
  end

  it "emits Int8 literals through the shared widening checked-add helper" do
    i8 = Tango::IR::Type.int(:i8)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new(
        "x",
        Tango::IR::LIR::CheckedArithmetic.new(
          Tango::IR::LIR::CheckedOperation::Add,
          Tango::IR::LIR::IntConst.new("127", i8),
          Tango::IR::LIR::IntConst.new("1", i8),
          i8,
          Tango::IR::CheckedArithmeticStrategy::WideningRoundTrip
        ),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("x := tangoAddI8(int8(127), int8(1))")
    source.should contain("if r != int64(int8(r)) {")
    source.should contain("return int8(r)")
  end

  it "emits UInt8 literals through the shared widening checked-add helper" do
    u8 = Tango::IR::Type.int(:u8)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new(
        "x",
        Tango::IR::LIR::CheckedArithmetic.new(
          Tango::IR::LIR::CheckedOperation::Add,
          Tango::IR::LIR::IntConst.new("255", u8),
          Tango::IR::LIR::IntConst.new("1", u8),
          u8,
          Tango::IR::CheckedArithmeticStrategy::WideningRoundTrip
        ),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("x := tangoAddU8(uint8(255), uint8(1))")
    source.should contain("if r != uint64(uint8(r)) {")
    source.should contain("return uint8(r)")
  end

  it "emits Int16 literals through the shared widening checked-add helper" do
    i16 = Tango::IR::Type.int(:i16)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new(
        "x",
        Tango::IR::LIR::CheckedArithmetic.new(
          Tango::IR::LIR::CheckedOperation::Add,
          Tango::IR::LIR::IntConst.new("32767", i16),
          Tango::IR::LIR::IntConst.new("1", i16),
          i16,
          Tango::IR::CheckedArithmeticStrategy::WideningRoundTrip
        ),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("x := tangoAddI16(int16(32767), int16(1))")
    source.should contain("if r != int64(int16(r)) {")
    source.should contain("return int16(r)")
  end

  it "emits UInt16 literals through the shared widening checked-add helper" do
    u16 = Tango::IR::Type.int(:u16)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new(
        "x",
        Tango::IR::LIR::CheckedArithmetic.new(
          Tango::IR::LIR::CheckedOperation::Add,
          Tango::IR::LIR::IntConst.new("65535", u16),
          Tango::IR::LIR::IntConst.new("1", u16),
          u16,
          Tango::IR::CheckedArithmeticStrategy::WideningRoundTrip
        ),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("x := tangoAddU16(uint16(65535), uint16(1))")
    source.should contain("if r != uint64(uint16(r)) {")
    source.should contain("return uint16(r)")
  end

  it "emits UInt64 literals and unsigned checked addition" do
    u64 = Tango::IR::Type.int(:u64)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new(
        "x",
        Tango::IR::LIR::CheckedArithmetic.new(
          Tango::IR::LIR::CheckedOperation::Add,
          Tango::IR::LIR::IntConst.new("18446744073709551615", u64),
          Tango::IR::LIR::IntConst.new("1", u64),
          u64,
          Tango::IR::CheckedArithmeticStrategy::UnsignedSameWidth
        ),
        Tango::IR::LIR::Assign::Mode::Declare
      ),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("x := tangoAddU64(uint64(18446744073709551615), uint64(1))")
    source.should contain("if c < a {")
    source.should_not contain("b < 0")
  end

  it "emits native channel make/send and a goroutine launch" do
    i32 = Tango::IR::Type.int(Tango::IR::Type::Width::I32)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new("ch", Tango::IR::LIR::MakeChan.new(i32, nil), Tango::IR::LIR::Assign::Mode::Declare),
      Tango::IR::LIR::ChanSend.new(Tango::IR::LIR::Temp.new("ch"), Tango::IR::LIR::IntConst.new("3")),
      Tango::IR::LIR::Spawn.new(Tango::IR::LIR::Temp.new("f")),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("ch := make(chan int32)")
    source.should contain("ch <- int32(3)")
    source.should contain("go f()")
  end

  it "emits a checked receive through the tangoChanRecv helper" do
    i32 = Tango::IR::Type.int(Tango::IR::Type::Width::I32)
    program = Tango::IR::LIR::Program.new([
      Tango::IR::LIR::Assign.new("v", Tango::IR::LIR::ChanReceive.new(Tango::IR::LIR::Temp.new("ch"), i32), Tango::IR::LIR::Assign::Mode::Declare),
    ] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("v := tangoChanRecv(ch)")
    source.should contain("func tangoChanRecv[T any](ch chan T) T")
    source.should contain(%(panic(&tangoChannelClosedError{message: "Channel is closed"})))
  end

  it "emits value receive? as comma-ok with a guarded carrier box" do
    i32 = Tango::IR::Type.int(:i32)
    union = i32.with_nil
    carrier = Tango::IR::LIR::UnionType.new(union, "maybeI32", [
      Tango::IR::LIR::UnionType::Variant.new("Nil", 0, nil),
      Tango::IR::LIR::UnionType::Variant.new("Int32", 1, i32),
    ])
    receive = Tango::IR::LIR::ChanReceiveMaybeBox.new(Tango::IR::LIR::Temp.new("ch"), i32, union)
    program = Tango::IR::LIR::Program.new(
      [Tango::IR::LIR::Assign.new("got", receive, Tango::IR::LIR::Assign::Mode::Declare)] of Tango::IR::LIR::Stmt,
      unions: [carrier]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should match(/__tango_received_\d+, __ok\d+ := <-ch/)
    source.should match(/if __ok\d+ \{/)
    source.should match(/= maybeI32\{tag: 1, vInt32: __tango_received_\d+\}/)
  end

  it "emits carrier String through typed MethodDecl and Switch nodes" do
    i32 = Tango::IR::Type.int(:i32)
    string = Tango::IR::Type.string
    union = Tango::IR::Type.union([i32, string])
    carrier = Tango::IR::LIR::UnionType.new(union, "intOrString", [
      Tango::IR::LIR::UnionType::Variant.new("Int32", 0, i32),
      Tango::IR::LIR::UnionType::Variant.new("String", 1, string),
    ])
    file = Tango::Target::Go::FromLIR.translate(Tango::IR::LIR::Program.new(
      [] of Tango::IR::LIR::Stmt,
      unions: [carrier]
    ))

    method = file.method_decls.first
    method.should be_a(Tango::Target::Go::IR::MethodDecl)
    method.name.should eq("String")
    switch = method.body.first.as(Tango::Target::Go::IR::Switch)
    switch.cases.size.should eq(3)
    switch.cases.last.label.should be_nil

    source = Tango::Target::Go::Source.emit(file)
    source.should contain("func (value intOrString) String() string")
    source.should contain("switch value.tag")
    source.should contain("return fmt.Sprint(value.vInt32)")
    source.should contain("return fmt.Sprint(value.vString)")
  end

  it "emits `.nil?` on a carrier as a nil-tag comparison, not a payload lookup" do
    i32 = Tango::IR::Type.int(:i32)
    union = i32.with_nil
    carrier = Tango::IR::LIR::UnionType.new(union, "maybeI32", [
      Tango::IR::LIR::UnionType::Variant.new("Nil", 0, nil),
      Tango::IR::LIR::UnionType::Variant.new("Int32", 1, i32),
    ])
    test = Tango::IR::LIR::TypeTest.new(
      Tango::IR::LIR::Temp.new("x"),
      union,
      Tango::IR::Type::NIL,
      Tango::IR::LIR::TypeTest::Strategy::CarrierNil
    )
    program = Tango::IR::LIR::Program.new(
      [Tango::IR::LIR::Assign.new("absent", test, Tango::IR::LIR::Assign::Mode::Declare)] of Tango::IR::LIR::Stmt,
      unions: [carrier]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))
    source.should contain("x.tag == 0")
  end

  it "emits a planned carrier conversion as a typed switch function" do
    i32 = Tango::IR::Type.int(:i32)
    string = Tango::IR::Type.string
    narrow = Tango::IR::Type.union([i32, string])
    wide = Tango::IR::Type.union([i32, string, Tango::IR::Type::NIL])
    mapping = Tango::IR::CarrierConversionMap.new(
      "widenIntOrString",
      "intOrString",
      "maybeIntOrString",
      [
        Tango::IR::CarrierConversionMap::Variant.new(i32, 0, 1, "Int32", "Int32"),
        Tango::IR::CarrierConversionMap::Variant.new(string, 1, 2, "String", "String"),
      ]
    )
    conversion = Tango::IR::LIR::UnionConversion.new(narrow, wide, mapping)
    carriers = [
      Tango::IR::LIR::UnionType.new(narrow, "intOrString", [
        Tango::IR::LIR::UnionType::Variant.new("Int32", 0, i32),
        Tango::IR::LIR::UnionType::Variant.new("String", 1, string),
      ]),
      Tango::IR::LIR::UnionType.new(wide, "maybeIntOrString", [
        Tango::IR::LIR::UnionType::Variant.new("Nil", 0, nil),
        Tango::IR::LIR::UnionType::Variant.new("Int32", 1, i32),
        Tango::IR::LIR::UnionType::Variant.new("String", 2, string),
      ]),
    ]
    file = Tango::Target::Go::FromLIR.translate(Tango::IR::LIR::Program.new(
      [] of Tango::IR::LIR::Stmt,
      unions: carriers,
      conversions: [conversion]
    ))

    function = expect_present(file.functions.find(&.name.==("widenIntOrString")))
    function.body.first.should be_a(Tango::Target::Go::IR::Switch)
    source = Tango::Target::Go::Source.emit(file)
    source.should contain("func widenIntOrString(value intOrString) maybeIntOrString")
    source.should contain("return maybeIntOrString{tag: 1, vInt32: value.vInt32}")
    source.should contain("return maybeIntOrString{tag: 2, vString: value.vString}")
  end

  it "emits a select as native comm clauses binding each arm's value directly" do
    i32 = Tango::IR::Type.int(Tango::IR::Type::Width::I32)
    chosen = Tango::IR::LIR::Select.new([
      Tango::IR::LIR::Select::Arm.new(
        Tango::IR::LIR::Select::Arm::Kind::Receive,
        Tango::IR::LIR::Temp.new("ch"), nil, "x", i32, [] of Tango::IR::LIR::Stmt),
      Tango::IR::LIR::Select::Arm.new(
        Tango::IR::LIR::Select::Arm::Kind::Receive,
        Tango::IR::LIR::Temp.new("done"), nil, nil, i32, [] of Tango::IR::LIR::Stmt),
    ] of Tango::IR::LIR::Select::Arm)
    program = Tango::IR::LIR::Program.new([chosen] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("select {")
    # The bound arm receives into the user's own var; the bare arm discards it.
    source.should contain("case x, __ok0 := <-ch:")
    source.should contain("case _, __ok1 := <-done:")
    # The closed-channel guard is inline per receive arm, with no shared carrier.
    source.should contain("if !__ok0 {")
    source.should contain(%(panic(&tangoChannelClosedError{message: "Channel is closed"})))
  end

  it "boxes a receive? select value only when its comma-ok flag is true" do
    i32 = Tango::IR::Type.int(:i32)
    union = i32.with_nil
    carrier = Tango::IR::LIR::UnionType.new(union, "maybeI32", [
      Tango::IR::LIR::UnionType::Variant.new("Nil", 0, nil),
      Tango::IR::LIR::UnionType::Variant.new("Int32", 1, i32),
    ])
    arm = Tango::IR::LIR::Select::Arm.new(
      Tango::IR::LIR::Select::Arm::Kind::ReceiveMaybeCarrier,
      Tango::IR::LIR::Temp.new("ch"), nil, "item", i32,
      [Tango::IR::LIR::Discard.new(Tango::IR::LIR::Temp.new("item"))] of Tango::IR::LIR::Stmt,
      union
    )
    program = Tango::IR::LIR::Program.new(
      [Tango::IR::LIR::Select.new([arm])] of Tango::IR::LIR::Stmt,
      unions: [carrier]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should match(/case __tango_received_\d+, __ok\d+ := <-ch:/)
    source.should contain("var item maybeI32")
    source.should match(/if __ok\d+ \{/)
    source.should match(/item = maybeI32\{tag: 1, vInt32: __tango_received_\d+\}/)
  end

  it "emits a send arm as a send comm clause and an else as a default clause" do
    i32 = Tango::IR::Type.int(Tango::IR::Type::Width::I32)
    chosen = Tango::IR::LIR::Select.new(
      [Tango::IR::LIR::Select::Arm.new(
        Tango::IR::LIR::Select::Arm::Kind::Send,
        Tango::IR::LIR::Temp.new("jobs"), Tango::IR::LIR::IntConst.new("42"), nil, i32,
        [] of Tango::IR::LIR::Stmt)] of Tango::IR::LIR::Select::Arm,
      [Tango::IR::LIR::Discard.new(Tango::IR::LIR::Temp.new("x"))] of Tango::IR::LIR::Stmt)
    program = Tango::IR::LIR::Program.new([chosen] of Tango::IR::LIR::Stmt)

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("case jobs <- int32(42):")
    source.should contain("default:")
  end

  it "emits buffered make, close, and a raw receive for receive?" do
    signal = Tango::IR::Type.klass("Signal")
    program = Tango::IR::LIR::Program.new(
      [
        Tango::IR::LIR::Assign.new("ch", Tango::IR::LIR::MakeChan.new(signal, Tango::IR::LIR::IntConst.new("1")), Tango::IR::LIR::Assign::Mode::Declare),
        Tango::IR::LIR::ChanClose.new(Tango::IR::LIR::Temp.new("ch")),
        Tango::IR::LIR::Assign.new("got", Tango::IR::LIR::ChanReceiveMaybe.new(Tango::IR::LIR::Temp.new("ch"), signal), Tango::IR::LIR::Assign::Mode::Declare),
      ] of Tango::IR::LIR::Stmt,
      [] of Tango::IR::LIR::Func,
      [Tango::IR::LIR::StructType.new("Signal", [] of Tango::IR::Field, true)]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("ch := make(chan *Signal, int32(1))")
    source.should contain("close(ch)")
    source.should contain("got := <-ch")
  end

  it "emits Mutex allocation, the *sync.Mutex type, and receiver-method lock/unlock" do
    mutex = Tango::IR::Type.klass("Mutex")
    lock = Tango::IR::LIR::ExternalTarget.new("go", nil, "Lock", true)
    unlock = Tango::IR::LIR::ExternalTarget.new("go", nil, "Unlock", true)
    program = Tango::IR::LIR::Program.new(
      [
        Tango::IR::LIR::Assign.new("mutex", Tango::IR::LIR::MakeMutex.new(mutex), Tango::IR::LIR::Assign::Mode::Declare),
        Tango::IR::LIR::ExternalCall.new(lock, [Tango::IR::LIR::Temp.new("mutex")] of Tango::IR::LIR::Value),
        Tango::IR::LIR::ExternalCall.new(unlock, [Tango::IR::LIR::Temp.new("mutex")] of Tango::IR::LIR::Value),
      ] of Tango::IR::LIR::Stmt,
      [Tango::IR::LIR::Func.new("take", [Tango::IR::LIR::Param.new("m", mutex)], nil, [] of Tango::IR::LIR::Stmt)],
      external_types: [go_mutex_type(mutex)]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain(%(import "sync"))
    source.should contain("mutex := &sync.Mutex{}")
    source.should contain("mutex.Lock()")
    source.should contain("mutex.Unlock()")
    source.should contain("func take(m *sync.Mutex)")
  end

  it "registers sync when a Mutex appears only in a spelled type" do
    mutex = Tango::IR::Type.klass("Mutex")
    program = Tango::IR::LIR::Program.new(
      [] of Tango::IR::LIR::Stmt,
      [Tango::IR::LIR::Func.new("take", [Tango::IR::LIR::Param.new("m", mutex)], nil, [] of Tango::IR::LIR::Stmt)],
      external_types: [go_mutex_type(mutex)]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain(%(import "sync"))
    source.should contain("func take(m *sync.Mutex)")
  end

  it "keeps the package-function binding form as pkg.Func(args)" do
    upcase = Tango::IR::LIR::ExternalTarget.new("go", "strings", "ToUpper")
    program = Tango::IR::LIR::Program.new(
      [
        Tango::IR::LIR::Assign.new("s", Tango::IR::LIR::ExternalCallValue.new(upcase, [Tango::IR::LIR::StringConst.new("hi")] of Tango::IR::LIR::Value), Tango::IR::LIR::Assign::Mode::Declare),
      ] of Tango::IR::LIR::Stmt
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain(%(strings.ToUpper("hi")))
  end

  it "spells a Channel(T) type as a native chan" do
    i32 = Tango::IR::Type.int(Tango::IR::Type::Width::I32)
    channel = Tango::IR::Type.klass("Channel", [i32] of Tango::IR::Type)
    program = Tango::IR::LIR::Program.new(
      [] of Tango::IR::LIR::Stmt,
      [Tango::IR::LIR::Func.new("take", [Tango::IR::LIR::Param.new("ch", channel)], nil, [] of Tango::IR::LIR::Stmt)],
      external_types: [go_channel_type(channel)]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("func take(ch chan int32)")
  end

  it "emits pointer-backed array operations through typed helpers and indexing" do
    i32 = Tango::IR::Type.int(:i32)
    array = Tango::IR::Type.array(i32)
    array_type = Tango::IR::LIR::ArrayType.new(array, i32, true)
    program = Tango::IR::LIR::Program.new(
      [
        Tango::IR::LIR::Assign.new("xs", Tango::IR::LIR::ArrayBuild.new(array, i32, Tango::IR::LIR::IntConst.new("2")), Tango::IR::LIR::Assign::Mode::Declare),
        Tango::IR::LIR::Discard.new(Tango::IR::LIR::ArraySet.new(Tango::IR::LIR::Temp.new("xs"), Tango::IR::LIR::IntConst.new("0"), Tango::IR::LIR::IntConst.new("7"), i32)),
        Tango::IR::LIR::Discard.new(Tango::IR::LIR::ArrayPush.new(Tango::IR::LIR::Temp.new("xs"), Tango::IR::LIR::IntConst.new("9"), i32)),
        Tango::IR::LIR::Assign.new("first", Tango::IR::LIR::ArrayGet.new(Tango::IR::LIR::Temp.new("xs"), Tango::IR::LIR::IntConst.new("0"), i32), Tango::IR::LIR::Assign::Mode::Declare),
        Tango::IR::LIR::Assign.new("size", Tango::IR::LIR::CollectionCount.new(Tango::IR::LIR::ArrayElements.new(Tango::IR::LIR::Temp.new("xs"), i32)), Tango::IR::LIR::Assign::Mode::Declare),
      ] of Tango::IR::LIR::Stmt,
      arrays: [array_type]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("xs := tangoArrayBuild[int32](int32(2))")
    source.should contain("tangoArraySet(xs, int32(0), int32(7))")
    source.should contain("tangoArrayPush(xs, int32(9))")
    source.should contain("first := (*xs)[int32(0)]")
    source.should contain("size := int32(len((*xs)))")
    source.should contain("func tangoArrayBuild[T any]")
  end

  it "requires the planned insertion-order hash representation before spelling hash helpers" do
    hash = Tango::IR::Type.hash(Tango::IR::Type.string, Tango::IR::Type.int(:i32))
    [{true, false}, {false, true}].each do |reference, ordered|
      program = Tango::IR::LIR::Program.new(
        [Tango::IR::LIR::Discard.new(Tango::IR::LIR::HashNew.new(hash))] of Tango::IR::LIR::Stmt,
        hashes: [Tango::IR::LIR::HashType.new(hash, reference: reference, ordered: ordered)]
      )

      expect_raises(Exception, "unsupported hash representation #{hash}: expected insertion-ordered reference") do
        Tango::Target::Go::FromLIR.translate(program)
      end
    end
  end

  it "spells a nilable channel as a native chan, not a pointer to Channel" do
    i32 = Tango::IR::Type.int(Tango::IR::Type::Width::I32)
    channel = Tango::IR::Type.klass("Channel", [i32] of Tango::IR::Type)
    nilable_channel = Tango::IR::Type.union([channel, Tango::IR::Type::NIL])
    program = Tango::IR::LIR::Program.new(
      [] of Tango::IR::LIR::Stmt,
      [Tango::IR::LIR::Func.new("take", [Tango::IR::LIR::Param.new("ch", nilable_channel)], nil, [] of Tango::IR::LIR::Stmt)],
      external_types: [go_channel_type(channel)]
    )

    source = Tango::Target::Go::Source.emit(Tango::Target::Go::FromLIR.translate(program))

    source.should contain("func take(ch chan int32)")
    source.should_not contain("*Channel")
  end
end
