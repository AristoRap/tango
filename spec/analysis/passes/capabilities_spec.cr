require "../../spec_helper"

private alias NIR = Tango::IR::NIR

describe Tango::Analysis::Passes::Capabilities do
  it "records Crystal-proven Enumerable and Sized conformances" do
    snapshot = Tango.pre_target_snapshot(<<-TN, filename: "capability_facts.tn")
      def sum(values : Enumerable(Int32)) : Int32
        total = 0
        values.each { |value| total = total + value }
        total
      end

      array = Array(Int32).new
      puts sum(array)
      puts sum(1..2)
      puts "".empty?
      TN

    program = expect_present(snapshot.nir)
    facts = expect_present(snapshot.facts)
    definitions = program.body.compact_map(&.as?(NIR::Def))

    sum_capabilities = definitions.select(&.name.==("sum")).flat_map do |definition|
      facts.capability_conformances[definition.id]
    end
    sum_capabilities.map { |fact| {fact.concrete.to_s, fact.capability.to_s} }.sort.should eq([
      {"Array(Int32)", "Enumerable(Int32)"},
      {"Range(Int32, Int32)", "Enumerable(Int32)"},
    ])

    empty = definitions.find { |definition| definition.name == "empty?" && definition.owner == Tango::IR::Type.string }
    empty.should_not be_nil
    facts.capability_conformances[expect_present(empty).id].should eq([
      Tango::Analysis::Facts::CapabilityConformance.new(Tango::IR::Type.string, Tango::IR::Type.klass("Sized")),
    ])
  end

  it "does not infer conformance from an each-shaped method" do
    body = NIR::Block.new(Tango::NodeId.new("body"), [] of NIR::Stmt, nil)
    definition = NIR::Def.new(Tango::NodeId.new("def"), "each", [] of NIR::Param, body, Tango::IR::Type::NIL, nil)
    program = NIR::Program.new([definition] of NIR::Stmt)
    facts = Tango::Analysis::Facts::Table.new

    Tango::Analysis::Passes::Capabilities.run(program, facts)

    facts.capability_conformances.should be_empty
  end

  it "solves generic Comparable restrictions for every supported ordered scalar" do
    source = String.build do |io|
      io << "def ordered(left : Comparable(T), right : T) : Bool forall T\n"
      io << "  left <= right\n"
      io << "end\n"
      {
        {"Int8", "1_i8"},
        {"UInt8", "1_u8"},
        {"Int16", "1_i16"},
        {"UInt16", "1_u16"},
        {"Int32", "1_i32"},
        {"UInt32", "1_u32"},
        {"Int64", "1_i64"},
        {"UInt64", "1_u64"},
        {"Float64", "1.0"},
        {"String", %("a")},
      }.each do |_type, literal|
        io << "puts ordered(#{literal}, #{literal})\n"
      end
    end
    snapshot = Tango.pre_target_snapshot(source, filename: "comparable_matrix.tn")
    program = expect_present(snapshot.nir)
    facts = expect_present(snapshot.facts)

    witnesses = program.body.compact_map(&.as?(NIR::Def)).select(&.name.==("ordered")).flat_map do |definition|
      facts.capability_conformances[definition.id]
    end
    witnesses.map { |fact| {fact.concrete.to_s, fact.capability.to_s} }.sort.should eq([
      {"Float64", "Comparable(Float64)"},
      {"Int16", "Comparable(Int16)"},
      {"Int32", "Comparable(Int32)"},
      {"Int64", "Comparable(Int64)"},
      {"Int8", "Comparable(Int8)"},
      {"String", "Comparable(String)"},
      {"UInt16", "Comparable(UInt16)"},
      {"UInt32", "Comparable(UInt32)"},
      {"UInt64", "Comparable(UInt64)"},
      {"UInt8", "Comparable(UInt8)"},
    ])
  end
end
