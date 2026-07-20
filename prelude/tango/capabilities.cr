# Shared language capabilities own derived behavior while concrete types supply
# the smallest operation that makes the behavior possible. These are ordinary
# Tango modules: including them does not imply a compiler representation or an
# optimization strategy.
module Comparable(T)
  abstract def <=>(other : T)

  def <(other : T) : Bool
    comparison = self <=> other
    comparison ? comparison < 0 : false
  end

  def <=(other : T) : Bool
    comparison = self <=> other
    comparison ? comparison <= 0 : false
  end

  def ==(other : T) : Bool
    {% if @type < Reference %}
      return true if self.same?(other)
    {% end %}

    comparison = self <=> other
    comparison ? comparison == 0 : false
  end

  def >(other : T) : Bool
    comparison = self <=> other
    comparison ? comparison > 0 : false
  end

  def >=(other : T) : Bool
    comparison = self <=> other
    comparison ? comparison >= 0 : false
  end
end

module Sized
  abstract def size : Int32

  def empty? : Bool
    self.size == 0
  end
end

# Eager traversal. Including types provide `each`; collection-producing
# operations deliberately materialize Arrays.
module Enumerable(T)
  abstract def each(& : T ->)

  @[TangoSemantic(:map)]
  def map(& : T -> U) : Array(U) forall U
    result = Array(U).new
    each do |element|
      result << yield element
    end
    result
  end

  @[TangoSemantic(:filter_keep)]
  def select(& : T -> Bool) : Array(T)
    result = Array(T).new
    each do |element|
      if yield element
        result << element
      end
    end
    result
  end

  @[TangoSemantic(:filter_reject)]
  def reject(& : T -> Bool) : Array(T)
    result = Array(T).new
    each do |element|
      unless yield element
        result << element
      end
    end
    result
  end

  @[TangoSemantic(:fold)]
  def reduce(initial : U, & : U, T -> U) : U forall U
    result = initial
    each do |element|
      result = yield result, element
    end
    result
  end
end

# Stable, eager indexed access. Concrete types provide only size and the
# unchecked operational leaf; the public surface and traversal are derived once
# so every conforming type has identical negative-index and iteration behavior.
module Indexable(T)
  include Enumerable(T)
  include Sized

  abstract def unsafe_fetch(index : Int32) : T

  @[TangoSemantic(:indexed_read)]
  def [](index : Int32) : T
    index = index + self.size if index < 0
    self.unsafe_fetch(index)
  end

  @[TangoSemantic(:each)]
  def each(& : T ->) : Nil
    index = 0
    while index < self.size
      yield self.unsafe_fetch(index)
      index = index + 1
    end
  end
end

# Mutable indexed access extends the same kernel with one unchecked write leaf.
# Deliberately leaves an invalid normalized index as a non-rescuable target
# runtime fault rather than adding a second exception policy here.
module MutableIndexable(T)
  include Indexable(T)

  abstract def unsafe_put(index : Int32, value : T) : T

  @[TangoSemantic(:indexed_write)]
  def []=(index : Int32, value : T) : T
    index = index + self.size if index < 0
    self.unsafe_put(index, value)
  end
end

# Stateful, one-shot traversal. `next` consumes the source and uses a sentinel
# whose type is distinct from every element value (including Nil). Transforming
# an Iterator stays lazy: the wrappers below consume their source only when
# their own `next` is called.
module Iterator(T)
  include Enumerable(T)

  struct Stop
    @[TangoInternal]
    def initialize(@stopped : Bool)
    end
  end

  abstract def next : T | Stop

  def stop : Stop
    Stop.new(true)
  end

  def each(& : T ->) : Nil
    while true
      value = self.next
      break if value.is_a?(Stop)
      yield value
    end
  end

  def map(&transform : T -> U) forall U
    MapIterator(typeof(self), T, U).new(self, transform)
  end

  def select(&predicate : T -> Bool)
    SelectIterator(typeof(self), T).new(self, predicate)
  end

  def reject(&predicate : T -> Bool)
    RejectIterator(typeof(self), T).new(self, predicate)
  end

  private struct MapIterator(I, T, U)
    include Iterator(U)

    def initialize(@iterator : I, @transform : T -> U)
    end

    def next : U | Iterator::Stop
      value = @iterator.next
      return Iterator::Stop.new(true) if value.is_a?(Iterator::Stop)
      @transform.call(value)
    end
  end

  private struct SelectIterator(I, T)
    include Iterator(T)

    def initialize(@iterator : I, @predicate : T -> Bool)
    end

    def next : T | Iterator::Stop
      while true
        value = @iterator.next
        return Iterator::Stop.new(true) if value.is_a?(Iterator::Stop)
        return value if @predicate.call(value)
      end
    end
  end

  private struct RejectIterator(I, T)
    include Iterator(T)

    def initialize(@iterator : I, @predicate : T -> Bool)
    end

    def next : T | Iterator::Stop
      while true
        value = @iterator.next
        return Iterator::Stop.new(true) if value.is_a?(Iterator::Stop)
        return value unless @predicate.call(value)
      end
    end
  end
end
