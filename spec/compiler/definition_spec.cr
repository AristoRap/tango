require "../spec_helper"

private SOURCE = "def add(a : Int32, b : Int32) : Int32\n  a + b\nend\n\nputs add(1, 2)"

private LOCAL_SOURCE = "x = 1\nputs x\n"

private BLOCK_SOURCE = <<-TN
  def twice(&block : Int32 -> Int32) : Int32
    block.call(block.call(1))
  end

  captured = 10
  puts twice { |n| n + captured }
  TN

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

private SAME_METHOD_SOURCE = <<-TN
  class Left
    def value : Int32
      1
    end
  end

  class Right
    def value : Int32
      2
    end
  end

  left = Left.new
  right = Right.new
  puts left.value
  puts right.value
  TN

private OVERLOAD_SOURCE = <<-TN
  def pick(x : Int32) : Int32
    x
  end

  def pick(x : String) : String
    x
  end

  puts pick(1)
  puts pick("s")
  TN

private OVERLOADED_INITIALIZER_SOURCE = <<-TN
  class Box
    def initialize(value : Int32)
      @kind = 1
    end

    def initialize(value : String)
      @kind = 2
    end
  end

  int_box = Box.new(1)
  string_box = Box.new("s")
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

describe Tango::Compiler::Editor::Definition do
  it "resolves both tokens of a class-method dispatch" do
    source = <<-TN
      class Reader
        def self.read(path : String) : String
          path
        end
      end

      puts Reader.read("measurements.txt")
      TN
    snapshot = Tango.pre_target_snapshot(source, filename: "class_method.tn")

    receiver = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "class_method.tn", 7, 6))
    method = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "class_method.tn", 7, 13))
    {receiver.line, receiver.column}.should eq({1, 7})
    {method.line, method.column}.should eq({2, 12})
  end

  it "resolves generated accessor calls to their typed source declarations" do
    snapshot = Tango.pre_target_snapshot(ACCESSOR_SOURCE, filename: "accessors.tn")

    getter = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "accessors.tn", 8, 15))
    setter = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "accessors.tn", 9, 15))
    property_getter = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "accessors.tn", 10, 15))
    property_setter = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "accessors.tn", 11, 10))

    {getter.line, getter.column, getter.size}.should eq({2, 10, 4})
    {setter.line, setter.column, setter.size}.should eq({3, 10, 9})
    {property_getter.line, property_getter.column, property_getter.size}.should eq({4, 12, 5})
    {property_setter.line, property_setter.column, property_setter.size}.should eq({4, 12, 5})
  end

  it "resolves a call position to the target def name" do
    snapshot = Tango.snapshot(SOURCE, filename: "def.tn")

    # `def add` — the name `add` starts at column 5 and is 3 chars wide.
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "def.tn", 5, 6))
    target.path.should eq("def.tn")
    target.line.should eq(1)
    target.column.should eq(5)
    target.size.should eq(3)
  end

  it "resolves from anywhere on the callee identifier, not just its first byte" do
    snapshot = Tango.snapshot(SOURCE, filename: "def.tn")

    # `add` in `puts add(1, 2)` spans columns 6..8; the middle/last byte must
    # resolve too (the single-byte-span bug only resolved column 6).
    {6, 7, 8}.each do |column|
      target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "def.tn", 5, column))
      target.line.should eq(1)
      target.column.should eq(5)
    end
  end

  it "resolves an instance-method call to its method definition" do
    snapshot = Tango.snapshot(CLASS_SOURCE, filename: "class.tn")

    # `p.x` on the last line — `x` is the callee; it must land on `def x`.
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "class.tn", 13, 8))
    target.line.should eq(7)
    target.size.should eq(1)
  end

  it "keeps same-named methods distinct by receiver owner" do
    snapshot = Tango.pre_target_snapshot(SAME_METHOD_SOURCE, filename: "owners.tn")

    left = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "owners.tn", 15, 13))
    right = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "owners.tn", 16, 14))
    left.line.should eq(2)
    right.line.should eq(8)
  end

  it "resolves same-named overloads by their concrete signature" do
    snapshot = Tango.pre_target_snapshot(OVERLOAD_SOURCE, filename: "overloads.tn")

    int_target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "overloads.tn", 9, 7))
    string_target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "overloads.tn", 10, 7))
    int_target.line.should eq(1)
    string_target.line.should eq(5)
  end

  it "distinguishes the class reference from constructor dispatch in `Point.new`" do
    snapshot = Tango.pre_target_snapshot(CLASS_SOURCE, filename: "class.tn")

    class_target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "class.tn", 12, 5))
    constructor_target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "class.tn", 12, 11))
    class_target.line.should eq(1)
    constructor_target.line.should eq(2) # `initialize` supplies the constructor body.
  end

  it "resolves overloaded constructors to their concrete initializer" do
    snapshot = Tango.pre_target_snapshot(OVERLOADED_INITIALIZER_SOURCE, filename: "initializer_overloads.tn")

    int_target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "initializer_overloads.tn", 11, 17))
    string_target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "initializer_overloads.tn", 12, 20))
    int_target.line.should eq(2)
    string_target.line.should eq(6)
  end

  it "resolves a `.new` type reference to its class" do
    snapshot = Tango.snapshot(CLASS_SOURCE, filename: "class.tn")

    # `Point` in `p = Point.new(1, 2)` (line 12, cols 5..9) → `class Point`
    # (line 1, name at column 7, 5 chars wide).
    {5, 7, 9}.each do |column|
      target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "class.tn", 12, column))
      target.line.should eq(1)
      target.column.should eq(7)
      target.size.should eq(5)
    end
  end

  it "resolves an instance-var access to its owning class" do
    snapshot = Tango.snapshot(CLASS_SOURCE, filename: "class.tn")

    # `@x` in `@x = x` (line 3, column 5) → `class Point` (line 1, column 7).
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "class.tn", 3, 5))
    target.line.should eq(1)
    target.column.should eq(7)
  end

  it "resolves a local read to its first assignment" do
    snapshot = Tango.snapshot(LOCAL_SOURCE, filename: "locals.tn")

    # `x` in `puts x` (line 2, col 6) → its declaration `x = 1` (line 1, col 1).
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "locals.tn", 2, 6))
    target.line.should eq(1)
    target.column.should eq(1)
    target.size.should eq(1)
  end

  it "resolves a param read to the param declaration" do
    snapshot = Tango.snapshot(SOURCE, filename: "def.tn")

    # `a` in `a + b` (line 2, col 3) → param `a` (line 1, col 9).
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "def.tn", 2, 3))
    target.line.should eq(1)
    target.column.should eq(9)
    target.size.should eq(1)
  end

  it "resolves a block-arg read to the block arg declaration" do
    snapshot = Tango.snapshot(BLOCK_SOURCE, filename: "block.tn")

    # `n` in `n + captured` (line 6, col 18) → block arg `n` (line 6, col 15).
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "block.tn", 6, 18))
    target.line.should eq(6)
    target.column.should eq(15)
    target.size.should eq(1)
  end

  it "resolves a captured local across a block boundary to its outer declaration" do
    snapshot = Tango.snapshot(BLOCK_SOURCE, filename: "block.tn")

    # `captured` inside the block (line 6, col 22) → outer `captured = 10`
    # (line 5, col 1) — the block captures the enclosing scope.
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "block.tn", 6, 22))
    target.line.should eq(5)
    target.column.should eq(1)
    target.size.should eq(8)
  end

  it "resolves a reassigned captured local inside a block to its outer declaration" do
    path = File.expand_path("../../examples/mutex_counter.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    # `count` on the RHS of `count = count + 1` inside the spawn block
    # (line 6, col 11) resolves to the outer `count = 0` (line 2, col 1) — the
    # block reassigns the captured local, it does not shadow it.
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, path, 6, 11))
    target.line.should eq(2)
    target.column.should eq(1)
    target.size.should eq(5)
  end

  it "resolves a select receive-arm's captured local to its arm binding" do
    path = File.expand_path("../../examples/select_receive.tn", __DIR__)
    snapshot = Tango.snapshot(File.read(path), filename: path)

    # `x` in `puts x` (line 6, col 8) → the arm binding `x` in
    # `when x = ch.receive` (line 5, col 6) — scoped to that arm's body.
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, path, 6, 8))
    target.line.should eq(5)
    target.column.should eq(6)
    target.size.should eq(1)
  end

  it "resolves a block-param read inside a def to its &block declaration" do
    snapshot = Tango.snapshot(BLOCK_SOURCE, filename: "block.tn")

    # `block` in `block.call` (line 2, col 3) → the def's `&block` param (line 1).
    target = expect_present(Tango::Compiler::Editor::Definition.at(snapshot, "block.tn", 2, 3))
    target.line.should eq(1)
    target.size.should eq(5)
  end

  it "returns nil for a position that is not a call to a def" do
    snapshot = Tango.snapshot(SOURCE, filename: "def.tn")

    Tango::Compiler::Editor::Definition.at(snapshot, "def.tn", 5, 1).should be_nil
  end

  it "returns nil when the snapshot has no NIR" do
    snapshot = Tango.snapshot("puts(", filename: "broken.tn")

    Tango::Compiler::Editor::Definition.at(snapshot, "broken.tn", 1, 1).should be_nil
  end
end
