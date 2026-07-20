module Tango
  module IR
    # A module contract Crystal has already proven for one concrete typed-def
    # instance. NIR carries it as metadata and analysis publishes the same
    # target-neutral value; neither layer reconstructs inclusion from methods.
    record CapabilityConformance, concrete : Type, capability : Type
  end
end
