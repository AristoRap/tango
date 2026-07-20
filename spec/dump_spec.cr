require "./spec_helper"
require "../src/tango/dump"

describe "phase dumps" do
  it "keeps sorted report aggregation, presentation, and reference mutation visible" do
    entry = File.join("examples", "weather_report.tn")
    snapshot = Tango.snapshot(File.read(entry), filename: entry)

    snapshot.diagnostics.should be_empty
    nir = Tango::Dump::NIR.render(snapshot)
    facts = Tango::Dump::Facts.render(snapshot)
    plans = Tango::Dump::Plans.render(snapshot)
    lir = Tango::Dump::LIR.render(snapshot)

    nir.should contain("Class StationStats { count : Int32, sum : Float64, minimum : Float64, maximum : Float64 }")
    nir.should contain("HashHasKey String, StationStats")
    nir.should contain("HashGet String, StationStats")
    nir.should contain("HashSet String, StationStats")
    nir.should contain("Def Array(String)#sort : Array(String)")
    nir.should contain("primitive StringCompare")
    nir.should contain("primitive NumericConvert")
    nir.should contain("primitive FloatIntrinsic")
    nir.should contain("FloatLiteral 10 : Float64")
    nir.should contain(%(StringLiteral "No weather records"))
    facts.should contain("internal_call initialize(StationStats, Float64)")
    plans.should contain("Hash(String, StationStats) hash_repr Reference order=Insertion")
    plans.should contain("constructor StationStats__new_Float64 -> initialize_StationStats_Float64")
    lir.should contain("Struct StationStats (count : Int32) (sum : Float64) (minimum : Float64) (maximum : Float64)")
    lir.should contain("Func add_StationStats_Float64")
    lir.should contain("FieldAssign minimum")
    lir.should contain("FieldAssign maximum")
    lir.should contain("Func sort_Arrayu28_Stringu29_")
    lir.should contain("StringCompare")
    lir.should contain("NumericConvert Int32 -> Float64")
    lir.should contain("FloatIntrinsic RoundEven Float64")
    lir.should contain("Assign st Declare Call StationStats__new_Float64 FloatConst Float64 10")
    lir.should contain(%(StringConst "No weather records"))
  end

  it "pins required definitions and their locations without runtime require policy" do
    entry = File.join("examples", "require_main.tn")
    math = File.expand_path(File.join("examples", "support", "require_main", "math.tn"))
    counter = File.expand_path(File.join("examples", "support", "require_main", "counter.tn"))
    snapshot = Tango.snapshot(File.read(entry), filename: entry)

    snapshot.diagnostics.should be_empty
    dumps = {
      "nir"   => Tango::Dump::NIR.render(snapshot),
      "facts" => Tango::Dump::Facts.render(snapshot),
      "plans" => Tango::Dump::Plans.render(snapshot),
      "lir"   => Tango::Dump::LIR.render(snapshot),
    }
    graph_header = Tango::Dump::SourceGraphHeader.render(snapshot.source)

    dumps.each_value { |dump| dump.should start_with(graph_header) }
    graph_header.should contain(%(source_graph entry="#{entry}"))
    graph_header.should contain(%(source_graph files=["#{counter}", "#{math}", "#{entry}"]))
    graph_header.should contain(%(source_graph edge from="#{entry}" request="./support/require_main/math" to="#{math}" @#{entry}:0...37))
    graph_header.should contain(%(source_graph edge from="#{math}" request="./counter" to="#{counter}" @#{math}:0...19))

    dumps["nir"].should contain("Def add : Int32 @#{math}:21...22")
    dumps["nir"].should contain("Class Counter { value : Int32 } @#{counter}:0...1")
    dumps["facts"].should contain("type Int32 @#{math}:61...62")
    dumps["facts"].should contain("field_ref Counter.value @#{counter}:55...56")
    dumps["plans"].should contain("def add_Int32_Int32 block_mode=Plain @#{math}:21...22")
    dumps["plans"].should contain("def value_Counter block_mode=Plain @#{counter}:16...17")
    dumps["lir"].should contain("Func add_Int32_Int32 (a : Int32) (b : Int32) : Int32 @#{math}:3:1")
    dumps["lir"].should contain("Func value_Counter (self : Counter) : Int32 @#{counter}:2:3")

    dumps.each_value { |dump| dump.should_not match(/\bRequire\b/) }
    snapshot.go_source.to_s.should_not contain("require \"")
  end
end
