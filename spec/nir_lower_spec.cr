require "./spec_helper"

private def nir_trace_for(example : String) : String
  path = File.join("examples", "#{example}.tn")
  snapshot = Tango.snapshot(File.read(path), filename: path)
  Tango::Dump::LowerTrace.render_nir(snapshot)
end

describe "NIR lowering seam trace" do
  it "pins recursive def lowering decisions" do
    nir_trace_for("recursive").chomp.should eq(<<-TRACE)
      (def id="nir19" name="factorial" lowered="factorial_Int32" return="Int32"
        (param id="nir4" name="n" type="Int32")
        (block id="nir18"
          (if id="nir17" type="Int32"
            (call id="nir7" name="<=" type="Bool" decision="primitive:Binary" operator="<="
              (local id="nir5" name="n" type="Int32")
              (int id="nir6" type="Int32" value="1")
            )
            (block id="nir9"
              (int id="nir8" type="Int32" value="1")
            )
            (block id="nir16"
              (call id="nir15" name="*" type="Int32" decision="primitive:CheckedMul" operator="*"
                (local id="nir10" name="n" type="Int32")
                (call id="nir14" name="factorial" type="Int32" decision="internal-call" lowered="factorial_Int32"
                  (call id="nir13" name="-" type="Int32" decision="primitive:CheckedSub" operator="-"
                    (local id="nir11" name="n" type="Int32")
                    (int id="nir12" type="Int32" value="1")
                  )
                )
              )
            )
          )
        )
      )
      (call id="nir3" name="puts" type="Nil" decision="external-go" lowered="fmt.Println"
        (call id="nir2" name="factorial" type="Int32" decision="internal-call" lowered="factorial_Int32"
          (int id="nir1" type="Int32" value="5")
        )
      )
      TRACE
  end

  it "pins monomorphized def lowering decisions" do
    nir_trace_for("monomorphic").chomp.should eq(<<-TRACE)
      (def id="nir10" name="identity" lowered="identity_Int32" return="Int32"
        (param id="nir7" name="x" type="Int32")
        (block id="nir9"
          (local id="nir8" name="x" type="Int32")
        )
      )
      (def id="nir14" name="identity" lowered="identity_String" return="String"
        (param id="nir11" name="x" type="String")
        (block id="nir13"
          (local id="nir12" name="x" type="String")
        )
      )
      (call id="nir3" name="puts" type="Nil" decision="external-go" lowered="fmt.Println"
        (call id="nir2" name="identity" type="Int32" decision="internal-call" lowered="identity_Int32"
          (int id="nir1" type="Int32" value="1")
        )
      )
      (call id="nir6" name="puts" type="Nil" decision="external-go" lowered="fmt.Println"
        (call id="nir5" name="identity" type="String" decision="internal-call" lowered="identity_String"
          (string id="nir4" type="String" value="hi")
        )
      )
      TRACE
  end

  it "shows lowering decisions nested inside generic NIR nodes" do
    trace = nir_trace_for("array_basics")

    trace.should contain("(indexed_read")
    trace.should contain("(call id=\"nir173\" name=\"-\" type=\"Int32\" decision=\"primitive:CheckedSub\"")
    trace.should match(/\(value_sequence[^\n]*\n\s+\(block/)
  end
end
