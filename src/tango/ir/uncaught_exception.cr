module Tango
  module IR
    # The language-level presentation policy for a Tango exception that escapes
    # the entrypoint. Planning selects it; LIR carries it; targets only spell it.
    enum UncaughtExceptionStrategy
      CrystalStyle
    end
  end
end
