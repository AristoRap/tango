# Deterministic membership collection. Set is ordinary Tango code over the
# existing insertion-ordered Hash; it needs no Set-specific compiler or target
# representation. Re-inserting an element leaves its first-insertion position
# unchanged because Hash assignment does not move an existing key.
class Set(T)
  include Enumerable(T)
  include Sized

  def initialize
    @entries = Hash(T, Bool).new
  end

  def add?(value : T) : Bool
    return false if @entries.has_key?(value)

    @entries[value] = true
    true
  end

  def add(value : T) : Set(T)
    add?(value)
    self
  end

  def <<(value : T) : Set(T)
    add(value)
  end

  def includes?(value : T) : Bool
    @entries.has_key?(value)
  end

  def size : Int32
    @entries.size
  end

  def each(& : T ->) : Nil
    index = 0
    while index < @entries.size
      yield @entries.unsafe_key_at(index)
      index = index + 1
    end
  end
end
