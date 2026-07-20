module Tango
  module IR
    # Target-neutral overflow-check families. Planning chooses one from the
    # analyzed integer type; lowering carries it and targets only spell it.
    enum CheckedArithmeticStrategy
      WideningRoundTrip
      SignedSameWidth
      UnsignedSameWidth
    end
  end
end
