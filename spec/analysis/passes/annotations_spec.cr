require "../../spec_helper"

private def call_with_annotations(id : Tango::NodeId, annotations : Array(Tango::IR::NIR::TargetAnnotation)) : Tango::IR::NIR::Call
  target = Tango::IR::NIR::CallTarget.new("puts", nil, annotations)
  Tango::IR::NIR::Call.new(
    id, "puts",
    [] of Tango::IR::NIR::Expr,
    [target] of Tango::IR::NIR::CallTarget,
    nil, nil, nil
  )
end

describe Tango::Analysis::Passes::Annotations do
  it "records Go external annotations into the fact table" do
    id = Tango::NodeId.new("call")
    ann = Tango::IR::NIR::TargetAnnotation.new(["Go"], ["fmt.Println"], [] of String)
    program = Tango::IR::NIR::Program.new([call_with_annotations(id, [ann])] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Annotations.run(program, table)

    callee = table.go_externals[id].first
    callee.package_name.should eq("fmt")
    callee.name.should eq("Println")
  end

  it "shares structured external binding identity between callables and types" do
    id = Tango::NodeId.new("call")
    call_ann = Tango::IR::NIR::TargetAnnotation.new(["Go"], ["sync.NewCond"], [] of String)
    mutex = Tango::IR::Type.klass("Mutex")
    type_ann = Tango::IR::NIR::TargetAnnotation.new(["GoType"], ["sync.Mutex"], ["pointer"])
    program = Tango::IR::NIR::Program.new(
      [call_with_annotations(id, [call_ann])] of Tango::IR::NIR::Stmt,
      {mutex => [type_ann]}
    )

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Annotations.run(program, table)

    call_binding = table.go_externals[id].first.binding
    type_binding = table.external_types[mutex].binding
    call_binding.should be_a(Tango::IR::ExternalBinding)
    type_binding.should be_a(Tango::IR::ExternalBinding)
    call_binding.package_name.should eq("sync")
    type_binding.package_name.should eq("sync")
    type_binding.name.should eq("Mutex")
  end

  it "leaves the table untouched when there are no annotations" do
    id = Tango::NodeId.new("call")
    program = Tango::IR::NIR::Program.new([call_with_annotations(id, [] of Tango::IR::NIR::TargetAnnotation)] of Tango::IR::NIR::Stmt)

    table = Tango::Analysis::Facts::Table.new
    Tango::Analysis::Passes::Annotations.run(program, table)

    table.go_externals.has_key?(id).should be_false
  end
end
