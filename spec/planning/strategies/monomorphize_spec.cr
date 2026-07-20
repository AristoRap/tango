require "../../spec_helper"

private def collect_named_calls(node : Tango::IR::NIR::Stmt, name : String, into : Array(Tango::IR::NIR::Call)) : Nil
  into << node if node.is_a?(Tango::IR::NIR::Call) && node.name == name
  Tango::IR::NIR::Walk.children(node).each { |child| collect_named_calls(child, name, into) }
end

describe Tango::Planning::Strategies::Monomorphize do
  it "includes concrete block signatures in def and call names" do
    snapshot = Tango.snapshot(<<-TN, filename: "block_monomorphs.tn")
      def apply(& : Int32 -> U) : U forall U
        yield 1
      end

      puts apply { |value| value + 1 }
      puts apply { |value| "ok" }
      TN

    program = expect_present(snapshot.nir)
    plans = expect_present(snapshot.plans)
    definitions = program.body.compact_map(&.as?(Tango::IR::NIR::Def)).select(&.name.== "apply")
    names = definitions.map { |definition| plans.monomorphs[definition.id].name }

    names.size.should eq(2)
    names.uniq.size.should eq(2)
    names.any?(&.includes?("Int32")).should be_true
    names.any?(&.includes?("String")).should be_true

    calls = [] of Tango::IR::NIR::Call
    Tango::IR::NIR::Walk.children(program).each { |node| collect_named_calls(node, "apply", calls) }
    call_names = calls.map { |call| plans.calls[call.id].as(Tango::Planning::Plans::InternalCall).name }
    call_names.sort.should eq(names.sort)
  end

  it "keeps overloaded yield block modes aligned with their resolved defs" do
    snapshot = Tango.pre_target_snapshot(<<-TN, filename: "overloaded_blocks.tn")
      def use(x : Int32, & : -> Int32) : Int32
        yield
      end

      def use(x : String, & : -> Nil) : Nil
        yield
      end

      puts use(1) { 1 }
      use("s") { puts "x" }
      TN

    program = expect_present(snapshot.nir)
    facts = expect_present(snapshot.facts)
    plans = expect_present(snapshot.plans)
    calls = [] of Tango::IR::NIR::Call
    Tango::IR::NIR::Walk.children(program).each { |node| collect_named_calls(node, "use", calls) }

    calls.each do |call|
      block = expect_present(call.block)
      resolved = facts.internal_calls[call.id]
      plans.closures[block.id].mode.should eq(plans.monomorphs[resolved.definition].block_mode)
    end
    int_call = expect_present(calls.find { |call| call.args.first.type == Tango::IR::Type.int(:i32) })
    string_call = expect_present(calls.find { |call| call.args.first.type == Tango::IR::Type.string })
    plans.closures[expect_present(int_call.block).id].mode.value?.should be_true
    plans.closures[expect_present(string_call.block).id].mode.protocol?.should be_true
  end
end
