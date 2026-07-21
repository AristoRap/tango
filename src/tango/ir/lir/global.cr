module Tango
  module IR
    module LIR
      class GlobalRef < Value
        getter name : String

        def initialize(@name : String)
        end
      end
    end
  end
end
