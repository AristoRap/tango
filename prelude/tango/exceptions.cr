# Tango exceptions ride Go panic/recover, but remain a typed language surface.
# message is deliberately non-nilable so the static target interface can
# expose it without naming a generated union carrier.
class Exception
  @message : String = ""

  def initialize(@message : String = "")
  end

  @[Primitive(:tango_external)]
  @[Go(".tangoMessage")]
  def message : String
  end
end

class OverflowError < Exception
end

class DivisionByZeroError < Exception
end

class ArgumentError < Exception
end

class KeyError < Exception
end

class TypeCastError < Exception
end

class IndexError < Exception
end

class Channel(T)
  class ClosedError < Exception
  end
end

@[Primitive(:tango_raise)]
def raise(message : String) : NoReturn
end

@[Primitive(:tango_raise)]
def raise(exception : Exception) : NoReturn
end
