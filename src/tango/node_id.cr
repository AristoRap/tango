module Tango
  record NodeId, value : String do
    def self.synthetic(prefix : String, ordinal : Int32) : self
      new("#{prefix}#{ordinal}")
    end

    def to_s(io : IO) : Nil
      io << @value
    end
  end

  class NodeIdSequence
    def initialize(@prefix : String)
      @next_ordinal = 0
    end

    def next : NodeId
      @next_ordinal += 1
      NodeId.synthetic(@prefix, @next_ordinal)
    end
  end
end
