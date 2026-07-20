# Crystal expands an array literal through `unsafe_build`, `to_unsafe`, and
# indexed writes. Keeping `to_unsafe` as an identity Array avoids exposing
# Pointer to Tango while preserving Crystal's normal typed expansion.
class Array(T)
  include MutableIndexable(T)

  @[Primitive(:tango_array_new)]
  def self.new : Array(T)
  end

  @[Primitive(:tango_array_build)]
  @[TangoInternal]
  def self.unsafe_build(size : Int32) : Array(T)
  end

  @[TangoInternal]
  def to_unsafe : Array(T)
    self
  end

  @[Primitive(:tango_array_get)]
  def unsafe_fetch(index : Int32) : T
  end

  @[Primitive(:tango_array_set)]
  def unsafe_put(index : Int32, value : T) : T
  end

  @[Primitive(:tango_array_size)]
  def size : Int32
  end

  @[Primitive(:tango_array_push)]
  def <<(value : T) : Array(T)
  end

  def first : T
    self[0]
  end

  def last : T
    self[size - 1]
  end

  # Crystal's Array#sort is a stable, non-mutating ordering through T#<=>.
  # This insertion-sort body deliberately composes from public Tango operations;
  # the target never receives a sorting primitive or chooses ordering policy.
  def sort : Array(T)
    result = Array(T).new
    each do |element|
      result << element
    end
    result.sort!
  end

  def sort! : Array(T)
    i = 1
    while i < size
      element = self[i]
      j = i
      while j > 0
        break unless (element <=> self[j - 1]) < 0
        self[j] = self[j - 1]
        j = j - 1
      end
      self[j] = element
      i = i + 1
    end
    self
  end

  # This first materialized Enumerable slice is Int32-driven. A generalized
  # additive identity belongs with the wider numeric protocol, not in codegen.
  def sum : Int32
    total = 0
    each do |element|
      total = total + element
    end
    total
  end
end

class Hash(K, V)
  include Sized

  @[Primitive(:tango_hash_new)]
  def self.new : Hash(K, V)
  end

  @[Primitive(:tango_hash_get)]
  def [](key : K) : V
  end

  @[Primitive(:tango_hash_set)]
  def []=(key : K, value : V) : V
  end

  @[Primitive(:tango_hash_fetch)]
  def fetch(key : K, default : V) : V
  end

  @[Primitive(:tango_hash_size)]
  def size : Int32
  end

  @[Primitive(:tango_hash_has_key)]
  def has_key?(key : K) : Bool
  end

  @[Primitive(:tango_hash_key_at)]
  @[TangoInternal]
  def unsafe_key_at(index : Int32) : K
  end

  def each(& : K, V ->) : Nil
    i = 0
    while i < size
      key = unsafe_key_at(i)
      yield key, self[key]
      i = i + 1
    end
  end
end

struct Range(B, E)
  include Enumerable(B)

  def initialize(@begin : B, @end : E, @exclusive : Bool)
  end

  @[TangoSemantic(:each)]
  def each(& : B ->) : Nil
    i = @begin
    if @exclusive
      while i < @end
        yield i
        i = i + 1
      end
    else
      while i <= @end
        yield i
        i = i + 1
      end
    end
  end
end
