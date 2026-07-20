require "../../spec_helper"

describe Tango::Planning::Strategies::Repr do
  it "plans every member of a non-nil union as a tagged carrier variant" do
    snapshot = Tango.snapshot(<<-TN, filename: "union_print.tn")
      def choose(number : Bool) : Int32 | String
        if number
          7
        else
          "seven"
        end
      end

      value = choose(true)
      TN

    union = Tango::IR::Type.union([
      Tango::IR::Type.int(:i32),
      Tango::IR::Type.string,
    ])
    repr = expect_present(snapshot.plans).reprs[union].as(Tango::Planning::Plans::CarrierRepr)

    repr.variants.map(&.payload).should eq(union.members)
    repr.variants.map(&.tag).should eq([0, 1])
  end

  it "plans every source carrier variant onto the wider carrier's tags" do
    snapshot = Tango.snapshot(<<-TN, filename: "union_widen.tn")
      def choose(number : Bool) : Int32 | String
        number ? 7 : "seven"
      end

      def widen(number : Bool, absent : Bool) : Int32 | String | Nil
        absent ? nil : choose(number)
      end

      value = widen(true, false)
      TN

    conversion = expect_present(snapshot.plans).carrier_conversions.values.first
    conversion.source.to_s.should eq("Int32 | String")
    conversion.target.to_s.should eq("Int32 | String | Nil")
    conversion.mapping.variants.map { |variant| {variant.member.to_s, variant.source_tag, variant.target_tag} }.should eq([
      {"Int32", 0, 1},
      {"String", 1, 2},
    ])
  end

  it "picks CarrierRepr for a nilable struct (value type), not PointerRepr" do
    snapshot = Tango.snapshot(<<-TN, filename: "nilable_struct.tn")
      struct Pair
        @left : Int32
        @right : Int32

        def initialize(@left : Int32, @right : Int32)
        end
      end

      def find(hit : Bool) : Pair?
        if hit
          Pair.new(1, 2)
        else
          nil
        end
      end

      p = find(true)
      TN

    pair = Tango::IR::Type.klass("Pair")
    repr = expect_present(snapshot.plans).reprs[pair.with_nil]
    repr.should be_a(Tango::Planning::Plans::CarrierRepr)
  end

  it "keeps PointerRepr for a nilable class (reference type)" do
    snapshot = Tango.snapshot(<<-TN, filename: "nilable_class.tn")
      class Point
        @x : Int32

        def initialize(@x : Int32)
        end
      end

      def find(hit : Bool) : Point?
        if hit
          Point.new(7)
        else
          nil
        end
      end

      p = find(true)
      TN

    point = Tango::IR::Type.klass("Point")
    repr = expect_present(snapshot.plans).reprs[point.with_nil]
    repr.should be_a(Tango::Planning::Plans::PointerRepr)
  end

  it "pins a prelude-bound Channel(T)? to PointerRepr" do
    snapshot = Tango.snapshot(<<-TN, filename: "nilable_channel.tn")
      def maybe(ch : Channel(Int32), hit : Bool) : Channel(Int32)?
        if hit
          ch
        else
          nil
        end
      end

      value = maybe(Channel(Int32).new, true)
      TN

    channel = Tango::IR::Type.klass("Channel", [Tango::IR::Type.int(:i32)] of Tango::IR::Type)
    expect_present(snapshot.facts).external_types[channel].shape.should eq(Tango::IR::ExternalType::Shape::NativeChannel)
    expect_present(snapshot.plans).reprs[channel.with_nil].should be_a(Tango::Planning::Plans::PointerRepr)
  end
end
