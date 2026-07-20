require "../spec_helper"

private def report_presentation_output(source : String) : String
  go_source = Tango.compile(source, filename: "report_presentation.tn")
  output = IO::Memory.new
  error = IO::Memory.new
  result = Tango::Toolchain::Go.run_source(go_source, "report_presentation.tn", output, error)

  error.to_s.should be_empty
  result.status.should eq(0)
  result.diagnostics.should be_empty
  output.to_s
end

describe "report presentation" do
  it "sorts stably by the concrete comparison and rounds ties to even" do
    source = <<-TN
      class Item
        getter key : Int32
        getter label : String

        def initialize(@key : Int32, @label : String)
        end

        def <=>(other : Item) : Int32
          return -1 if key < other.key
          return 1 if key > other.key
          0
        end
      end

      items = [Item.new(2, "first-two"), Item.new(1, "one"), Item.new(2, "second-two")]
      items.sort.each do |item|
        puts item.label
      end

      puts 2.5.round
      puts 3.5.round
      puts 3.to_f
      TN

    report_presentation_output(source).should eq("one\nfirst-two\nsecond-two\n2.0\n4.0\n3.0\n")
  end
end
