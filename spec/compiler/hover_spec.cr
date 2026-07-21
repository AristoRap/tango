require "../spec_helper"

private CLASS_SOURCE = <<-TN
  class Point
    def initialize(x : Int32, y : Int32)
      @x = x
      @y = y
    end

    def x : Int32
      @x
    end
  end

  p = Point.new(1, 2)
  puts p.x
  TN

private NILABLE_SOURCE = <<-TN
  def maybe(hit : Bool) : Int32?
    if hit
      5
    else
      nil
    end
  end

  x = maybe(true)
  if x
    puts x
  end
  TN

private BLOCK_SOURCE = <<-TN
  def twice(&block : Int32 -> Int32) : Int32
    block.call(block.call(1))
  end

  captured = 10
  puts twice { |n| n + captured }
  TN

private ACCESSOR_SOURCE = <<-TN
  class Settings
    getter name : String = "tango"
    setter threshold : Int32 = 1
    property count : Int32 = 2
  end

  settings = Settings.new
  puts settings.name
  puts(settings.threshold = 3)
  puts settings.count
  settings.count = 4
  TN

private def hover_text(snapshot, path : String, line : Int32, column : Int32)
  Tango::Compiler::Editor::Hover.at(snapshot, path, line, column).try do |hover|
    Tango::Compiler::Editor::HoverText.render(hover)
  end
end

private def hover_markdown(snapshot, path : String, line : Int32, column : Int32)
  Tango::Compiler::Editor::Hover.at(snapshot, path, line, column).try do |hover|
    Tango::Compiler::Editor::HoverMarkdown.render(hover)
  end
end

describe Tango::Compiler::Editor::Hover do
  it "renders integer-system methods through the generic method-site projection" do
    source = "puts(1_u64 & 3_u64)\nputs(\"42\".to_u16)"
    snapshot = Tango.pre_target_snapshot(source, filename: "integer_hover.tn")

    hover_text(snapshot, "integer_hover.tn", 1, 12).should eq("UInt64#&(UInt64) : UInt64")
    hover_text(snapshot, "integer_hover.tn", 2, 12).should eq("String#to_u16 : UInt16")
  end

  it "renders a rescue binding with its bundled filesystem exception type" do
    source = <<-TN
      require "tango/fs"
      begin
        File.read("missing.txt")
      rescue ex : File::NotFoundError
        puts ex.message
      end
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: "file_error_hover.tn")

    hover_text(snapshot, "file_error_hover.tn", 4, 8).should eq("ex : File::NotFoundError")
  end

  it "renders the generic sorting contract and its concrete comparison leaf" do
    source = "names = [\"Berlin\", \"Amsterdam\"]\nputs names.sort.first\nputs(\"b\" <=> \"a\")"
    snapshot = Tango.pre_target_snapshot(source, filename: "sorting_hover.tn")

    hover_text(snapshot, "sorting_hover.tn", 2, 12).should eq("Array(String)#sort : Array(String)")
    hover_text(snapshot, "sorting_hover.tn", 3, 11).should eq("String#<=>(String) : Int32")
  end

  it "renders the concrete Float64 ordering leaf through generic method hover" do
    {
      {"<", "puts(1.0 < 2.0)", 10, "Float64#<(Float64) : Bool"},
      {"<=", "puts(1.0 <= 2.0)", 10, "Float64#<=(Float64) : Bool"},
      {"<=>", "puts((1.0 <=> 2.0).is_a?(Int32))", 12, "Float64#<=>(Float64) : (Int32 | Nil)"},
    }.each do |operator, source, column, expected|
      path = "float_#{operator.bytesize}_ordering.tn"
      snapshot = Tango.pre_target_snapshot(source, filename: path)
      hover_text(snapshot, path, 1, column).should eq(expected)
    end
  end

  it "renders Float64 intrinsic, conversion, and mixed arithmetic methods generically" do
    source = "puts 2.5.abs\nputs 2.5.to_i16\nputs 2_i8 + 0.5"
    snapshot = Tango.pre_target_snapshot(source, filename: "float_system_hover.tn")

    hover_text(snapshot, "float_system_hover.tn", 1, 10).should eq("Float64#abs : Float64")
    hover_text(snapshot, "float_system_hover.tn", 2, 10).should eq("Float64#to_i16 : Int16")
    hover_text(snapshot, "float_system_hover.tn", 3, 11).should eq("Int8#+(Float64) : Float64")
  end

  it "separates a class-method receiver hover from its callable hover" do
    source = <<-TN
      class Reader
        def self.read(path : String) : String
          path
        end
      end

      puts Reader.read("measurements.txt")
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: "class_method.tn")

    hover_text(snapshot, "class_method.tn", 7, 6).should eq("class Reader")
    hover_text(snapshot, "class_method.tn", 7, 13).should eq("Reader.read(String) : String")
  end

  it "renders generated accessor signatures at declarations and calls" do
    snapshot = Tango.pre_target_snapshot(ACCESSOR_SOURCE, filename: "accessors.tn")

    hover_text(snapshot, "accessors.tn", 2, 10).should eq("Settings#name : String")
    hover_text(snapshot, "accessors.tn", 8, 15).should eq("Settings#name : String")
    hover_text(snapshot, "accessors.tn", 9, 15).should eq("Settings#threshold=(Int32) : Int32")
    hover_text(snapshot, "accessors.tn", 10, 15).should eq("Settings#count : Int32")
    hover_text(snapshot, "accessors.tn", 11, 10).should eq("Settings#count=(Int32) : Int32")
  end

  it "renders a non-default integer width from the shared structured type" do
    source = "x = 4_i64\nputs x"
    snapshot = Tango.snapshot(source, filename: "int64.tn")

    hover_text(snapshot, "int64.tn", 1, 1).should eq("x : Int64")
    hover_text(snapshot, "int64.tn", 2, 6).should eq("x : Int64")
  end

  it "renders a narrow integer width from the shared structured type" do
    source = "x = 4_i8\nputs x"
    snapshot = Tango.snapshot(source, filename: "int8.tn")

    hover_text(snapshot, "int8.tn", 1, 1).should eq("x : Int8")
    hover_text(snapshot, "int8.tn", 2, 6).should eq("x : Int8")
  end

  it "renders an unsigned narrow width from the shared structured type" do
    source = "x = 4_u8\nputs x"
    snapshot = Tango.snapshot(source, filename: "uint8.tn")

    hover_text(snapshot, "uint8.tn", 1, 1).should eq("x : UInt8")
    hover_text(snapshot, "uint8.tn", 2, 6).should eq("x : UInt8")
  end

  it "renders a signed 16-bit width from the shared structured type" do
    source = "x = 4_i16\nputs x"
    snapshot = Tango.snapshot(source, filename: "int16.tn")

    hover_text(snapshot, "int16.tn", 1, 1).should eq("x : Int16")
    hover_text(snapshot, "int16.tn", 2, 6).should eq("x : Int16")
  end

  it "renders an unsigned 16-bit width from the shared structured type" do
    source = "x = 4_u16\nputs x"
    snapshot = Tango.snapshot(source, filename: "uint16.tn")

    hover_text(snapshot, "uint16.tn", 1, 1).should eq("x : UInt16")
    hover_text(snapshot, "uint16.tn", 2, 6).should eq("x : UInt16")
  end

  it "renders an unsigned integer width from the shared structured type" do
    source = "x = 4_u64\nputs x"
    snapshot = Tango.snapshot(source, filename: "uint64.tn")

    hover_text(snapshot, "uint64.tn", 1, 1).should eq("x : UInt64")
    hover_text(snapshot, "uint64.tn", 2, 6).should eq("x : UInt64")
  end

  it "renders an instance-var access as its field's name and type" do
    snapshot = Tango.snapshot(CLASS_SOURCE, filename: "class.tn")

    # `@x` in `@x = x` (line 3, column 5) and in the getter (line 8, column 5).
    hover_text(snapshot, "class.tn", 3, 5).should eq("x : Int32")
    hover_text(snapshot, "class.tn", 8, 5).should eq("x : Int32")
  end

  it "renders a nilable local as an explicit union — coevolution, no hover-specific fact" do
    snapshot = Tango.snapshot(NILABLE_SOURCE, filename: "nilable.tn")

    # `x` in `x = maybe(true)` (line 9, column 1) — hover reads the same
    # structured union as every phase but preserves the explicit Nil member.
    hover_text(snapshot, "nilable.tn", 9, 1).should eq("x : (Int32 | Nil)")
    # The condition still sees the nilable slot; inside its truthy branch,
    # Crystal's occurrence type is narrowed to Int32.
    hover_text(snapshot, "nilable.tn", 10, 4).should eq("x : (Int32 | Nil)")
    hover_text(snapshot, "nilable.tn", 11, 8).should eq("x : Int32")
  end

  it "renders a `.new` type reference as its class" do
    snapshot = Tango.snapshot(CLASS_SOURCE, filename: "class.tn")

    # `Point` in `p = Point.new(1, 2)` (line 12, column 5).
    hover_text(snapshot, "class.tn", 12, 5).should eq("class Point")
    # `new` is constructor dispatch, distinct from the `Point` type token.
    hover_text(snapshot, "class.tn", 12, 11).should eq("Point.new(Int32, Int32) : Point")
  end

  it "renders a typed user-class method signature on the method token" do
    snapshot = Tango.snapshot(CLASS_SOURCE, filename: "class.tn")

    hover_text(snapshot, "class.tn", 7, 7).should eq("Point#x : Int32")
    hover_text(snapshot, "class.tn", 13, 8).should eq("Point#x : Int32")
  end

  it "returns nil away from any reference" do
    snapshot = Tango.snapshot(CLASS_SOURCE, filename: "class.tn")

    hover_text(snapshot, "class.tn", 13, 1).should be_nil
  end

  it "notes a local captured by a goroutine — the escape fact's consumer" do
    # The driving example itself is the fixture: `ch` is captured by the
    # `spawn { … }` block, whose BlockFacts.escapes is true. Hover surfaces that
    # so a reader sees the local outlives its frame into a goroutine.
    path = File.expand_path("../../examples/spawn_channel.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    # `ch` inside `spawn { ch.send(1 + 2) }` (line 2, column 9).
    hover_text(snapshot, path, 2, 9).should eq("ch : Channel(Int32) (captured by a goroutine)")
    hover_markdown(snapshot, path, 2, 9).should eq(<<-MARKDOWN.chomp)
      ```tango
      ch : Channel(Int32)
      ```

      ---

      *Captured by a goroutine.*
      MARKDOWN
    # `ch` at its declaration `ch = Channel(Int32).new` (line 1, column 1) — the
    # same captured variable, so the note follows the local, not the occurrence.
    hover_text(snapshot, path, 1, 1).should eq("ch : Channel(Int32) (captured by a goroutine)")
  end

  it "notes a Mutex captured by a goroutine, reusing the escape fact" do
    # `mutex` in mutex_counter.tn is captured by each `spawn do … end` block —
    # the same goroutine-capture note falls out for the new Mutex type.
    path = File.expand_path("../../examples/mutex_counter.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    # Declaration `mutex = Mutex.new` (line 1, column 1).
    hover_text(snapshot, path, 1, 1).should eq("mutex : Mutex (captured by a goroutine)")
    # `mutex.lock` inside the first spawn block (line 5, column 3).
    hover_text(snapshot, path, 5, 3).should eq("mutex : Mutex (captured by a goroutine)")
    # `count = count + 1` reassigns the outer local — a captured write, not a
    # fresh block-local, so hover flags it too (line 6, column 3).
    hover_text(snapshot, path, 6, 3).should eq("count : Int32 (captured by a goroutine)")
  end

  it "renders a block parameter, a captured local, and a block argument" do
    snapshot = Tango.snapshot(BLOCK_SOURCE, filename: "block.tn")

    # `&block` parameter (line 1, column 12).
    hover_text(snapshot, "block.tn", 1, 12).should eq("block : (Int32) -> Int32")
    # `captured` inside the block body (line 6, column 22).
    hover_text(snapshot, "block.tn", 6, 22).should eq("captured : Int32")
    # `n` block argument, referenced in the body (line 6, column 18).
    hover_text(snapshot, "block.tn", 6, 18).should eq("n : Int32")
    # `block` referenced in `block.call` resolves to the same declaration
    # signature as `&block`, rather than exposing its internal Proc encoding.
    hover_text(snapshot, "block.tn", 2, 3).should eq("block : (Int32) -> Int32")
  end

  it "keys capture notes by declaration identity, not by local name" do
    source = <<-TN
      x = 1
      spawn { puts x }

      def value : Int32
        x = 2
        x
      end

      puts value
      TN
    snapshot = Tango.snapshot(source, filename: "same_name.tn")

    hover_text(snapshot, "same_name.tn", 1, 1).should eq("x : Int32 (captured by a goroutine)")
    hover_text(snapshot, "same_name.tn", 5, 3).should eq("x : Int32")
    hover_text(snapshot, "same_name.tn", 6, 3).should eq("x : Int32")
  end

  it "returns structured method data before presentation" do
    snapshot = Tango.snapshot(CLASS_SOURCE, filename: "class.tn")
    hover = expect_present(Tango::Compiler::Editor::Hover.at(snapshot, "class.tn", 13, 8))
    subject = hover.subject.as(Tango::Compiler::Editor::Hover::CallableSubject)

    subject.owner.to_s.should eq("Point")
    subject.name.should eq("x")
    subject.parameter_types.should be_empty
    subject.return_type.to_s.should eq("Int32")
    hover.symbol.should_not be_nil
    hover.range.start_offset.should eq(expect_present(CLASS_SOURCE.index("p.x")) + 2)
  end

  it "renders a select receive-arm's captured local as its element type" do
    path = File.expand_path("../../examples/select_receive.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    # `x` at its arm binding (line 5, col 6) and its use `puts x` (line 6, col 8).
    hover_text(snapshot, path, 5, 6).should eq("x : Int32")
    hover_text(snapshot, path, 6, 8).should eq("x : Int32")
  end

  it "renders receive? select bindings as explicit unions and preserves narrowing" do
    path = File.expand_path("../../examples/concurrency_edges.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    hover_text(snapshot, path, 26, 6).should eq("item : (Int32 | Nil)")
    hover_text(snapshot, path, 27, 6).should eq("item : (Int32 | Nil)")
    hover_text(snapshot, path, 28, 10).should eq("item : Int32")
  end

  it "renders a rescue binding as source-level Exception, without Crystal's virtual-type +" do
    path = File.expand_path("../../examples/rescue_basic.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    # Binding in `rescue ex` and use in `puts ex.message`.
    hover_text(snapshot, path, 8, 8).should eq("ex : Exception")
    hover_text(snapshot, path, 9, 8).should eq("ex : Exception")
  end

  it "renders typed Array method signatures on the method token" do
    path = File.expand_path("../../examples/array_basics.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    hover_text(snapshot, path, 2, 9).should eq("Array(Int32)#size : Int32")
    hover_text(snapshot, path, 3, 9).should eq("Array(Int32)#first : Int32")
  end

  it "renders typed Hash method signatures on the method token" do
    path = File.expand_path("../../examples/hash_core_dispatch.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    hover_text(snapshot, path, 45, 8).should eq("Hash(String, Int32)#fetch(String, Int32) : Int32")
  end
end
