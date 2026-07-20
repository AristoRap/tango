module Tango
  module IR
    module LIR
      # Lowering commits the ordered exception-selection policy once for both
      # statement and value handlers. The body remains generic because a value
      # handler needs an Arm (statements plus terminal value), while a statement
      # handler needs only its statements.
      class RescueClause(T)
        getter types : Array(IR::Type)
        getter binding : String?
        getter body : T
        # A clause catches everything when it names no type (bare `rescue`) or
        # the root `Exception`. Lowering decides this; targets only read it.
        getter? catch_all : Bool

        def initialize(@types : Array(IR::Type), @binding : String?, @body : T, @catch_all : Bool)
        end
      end
    end
  end
end
