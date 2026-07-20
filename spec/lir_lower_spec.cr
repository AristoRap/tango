require "./spec_helper"

private def lir_trace_for(example : String) : String
  path = File.join("examples", "#{example}.tn")
  snapshot = Tango.snapshot(File.read(path), filename: path)
  Tango::Dump::LowerTrace.render_lir(snapshot)
end

describe "LIR lowering seam trace" do
  it "pins recursive def lowered shapes" do
    lir_trace_for("recursive").chomp.should eq(<<-TRACE)
      (func name="factorial_Int32" return="Int32"
        (param name="n" type="Int32")
        (abrupt shape="Return"
          (if-value type="Int32"
            (binary operator="<="
              (temp name="n")
              (int type="Int32" value="1")
            )
            (int type="Int32" value="1")
            (checked-arithmetic operation="Mul" type="Int32" strategy="WideningRoundTrip"
              (temp name="n")
              (call name="factorial_Int32"
                (checked-arithmetic operation="Sub" type="Int32" strategy="WideningRoundTrip"
                  (temp name="n")
                  (int type="Int32" value="1")
                )
              )
            )
          )
        )
      )
      (external-call target="fmt.Println"
        (call name="factorial_Int32"
          (int type="Int32" value="5")
        )
      )
      TRACE
  end

  it "nests a while loop's body inside its own closing paren, not after it" do
    lir_trace_for("while").chomp.should eq(<<-TRACE)
      (assign target="x" mode="Declare"
        (int type="Int32" value="0")
      )
      (while
        (binary operator="<"
          (temp name="x")
          (int type="Int32" value="3")
        )
        (external-call target="fmt.Println"
          (temp name="x")
        )
        (assign target="x" mode="Reassign"
          (checked-arithmetic operation="Add" type="Int32" strategy="WideningRoundTrip"
            (temp name="x")
            (int type="Int32" value="1")
          )
        )
      )
      TRACE
  end

  it "pins monomorphized def lowered shapes" do
    lir_trace_for("monomorphic").chomp.should eq(<<-TRACE)
      (func name="identity_Int32" return="Int32"
        (param name="x" type="Int32")
        (abrupt shape="Return"
          (temp name="x")
        )
      )
      (func name="identity_String" return="String"
        (param name="x" type="String")
        (abrupt shape="Return"
          (temp name="x")
        )
      )
      (external-call target="fmt.Println"
        (call name="identity_Int32"
          (int type="Int32" value="1")
        )
      )
      (external-call target="fmt.Println"
        (call name="identity_String"
          (string value="hi")
        )
      )
      TRACE
  end

  it "shows decisions nested inside generic value and statement nodes" do
    trace = lir_trace_for("array_basics")
    trace.should contain("(func name=\"last_Arrayu28_Int32u29_\" return=\"Int32\"")
    trace.should contain("(call name=\"u5b_u5d__Arrayu28_Int32u29__Int32\"")
    trace.should contain("(checked-arithmetic operation=\"Sub\" type=\"Int32\" strategy=\"WideningRoundTrip\"")

    lir_trace_for("select_send").should contain(<<-TRACE)
      (select
        (temp name="jobs")
        (int type="Int32" value="42")
        (external-call target="fmt.Println"
          (int type="Int32" value="1")
        )
        (temp name="replies")
        (external-call target="fmt.Println"
          (temp name="r")
        )
      )
      TRACE
  end
end
