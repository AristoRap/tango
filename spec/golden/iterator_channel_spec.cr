require "../spec_helper"
require "../../src/tango/dump"

private alias IteratorNIR = Tango::IR::NIR
private alias IteratorLIR = Tango::IR::LIR
private alias IteratorFacts = Tango::Analysis::Facts

private def collect_iterator_nodes(node : IteratorNIR::Stmt, operations : Array(IteratorNIR::ChannelOp)) : Nil
  if operation = node.as?(IteratorNIR::ChannelOp)
    operations << operation if operation.kind.next_state?
  end
  IteratorNIR::Walk.children(node).each { |child| collect_iterator_nodes(child, operations) }
end

private def collect_iterator_lir(node : IteratorLIR::Walk::Node, into : Array(IteratorLIR::Walk::Node)) : Nil
  into << node
  children = case node
             when IteratorLIR::Stmt  then IteratorLIR::Walk.children(node)
             when IteratorLIR::Value then IteratorLIR::Walk.children(node)
             else                         [] of IteratorLIR::Walk::Node
             end
  children.each { |child| collect_iterator_lir(child, into) }
end

describe "Iterator and Channel" do
  it "preserves stop semantics, lazy layouts, traversal facts, and conservative capability laws" do
    source_path = File.join("examples", "iterator_channel.tn")
    snapshot = Tango.snapshot(File.read(source_path), filename: source_path)
    program = expect_present(snapshot.nir)
    facts = expect_present(snapshot.facts)
    lir = expect_present(snapshot.lir)
    operations = [] of IteratorNIR::ChannelOp
    IteratorNIR::Walk.children(program).each { |node| collect_iterator_nodes(node, operations) }

    operations.size.should eq(2)
    operations.each do |operation|
      traversal = facts.traversals[operation.id]
      traversal.blocking.should eq(IteratorFacts::BlockingBehavior::MayBlock)
      traversal.consumption.should eq(IteratorFacts::ConsumptionBehavior::Destructive)
      traversal.replayability.should eq(IteratorFacts::Replayability::OneShot)
      traversal.finiteness.should eq(IteratorFacts::Finiteness::Unknown)
      traversal.encounter_order.should eq(IteratorFacts::EncounterOrder::Unknown)
    end
    Tango::Dump::Facts.render(snapshot).should contain(
      "traversal_facts blocking=MayBlock consumption=Destructive replay=OneShot finiteness=Unknown order=Unknown"
    )

    next_states = lir.types.select { |type| type.type.name == "ChannelNextState" }
    next_states.map(&.type).to_set.should eq(Set{
      Tango::IR::Type.klass("ChannelNextState", [Tango::IR::Type.int(:i32).with_nil]),
      Tango::IR::Type.klass("ChannelNextState", [Tango::IR::Type.int(:i32)]),
    })
    maps = lir.types.select { |type| type.type.name == "MapIterator" }
    maps.size.should eq(2)
    maps.map(&.name).uniq.size.should eq(2)
    maps.each { |type| type.name.should_not contain(":") }

    values = [] of IteratorLIR::Walk::Node
    lir.body.each { |node| collect_iterator_lir(node, values) }
    lir.functions.each { |function| function.body.each { |node| collect_iterator_lir(node, values) } }
    values.count(&.is_a?(IteratorLIR::ChanReceiveState)).should eq(2)
    Tango::Dump::LIR.render(snapshot).should contain(
      "ChanReceiveState Int32? -> ChannelNextState(Int32?) fields=value,open"
    )

    custom = Tango.snapshot(<<-TN, filename: "custom_iterator.tn")
      struct Counter
        include Iterator(Int32)

        def next : Int32 | Iterator::Stop
          stop
        end
      end

      def advance(value : Iterator(Int32))
        value.next
      end

      advance(Counter.new)
      TN
    custom_facts = expect_present(custom.facts)
    custom_facts.traversals.should be_empty
    custom_facts.capability_conformances.values.flatten.any? do |conformance|
      conformance.concrete.name == "Counter" && conformance.capability.name == "Iterator"
    end.should be_true
  end
end
