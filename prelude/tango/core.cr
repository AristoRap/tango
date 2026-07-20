class Reference
  @[Primitive(:reference_identity)]
  def same?(other : Reference) : Bool
  end

  @[Primitive(:binary)]
  def ==(other : self) : Bool
  end

  def !=(other : self) : Bool
    !(self == other)
  end

  def ===(other : self) : Bool
    self == other
  end
end

struct Value
  @[Primitive(:binary)]
  def ==(other : self) : Bool
  end

  def !=(other : self) : Bool
    !(self == other)
  end

  def ===(other : self) : Bool
    self == other
  end
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end
end

struct Bool
  @[Primitive(:binary)]
  def ==(other : Bool) : Bool
  end

  @[Primitive(:binary)]
  def !=(other : Bool) : Bool
  end
end
