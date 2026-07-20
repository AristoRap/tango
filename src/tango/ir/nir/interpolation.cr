module Tango
  module IR
    module NIR
      # Crystal has already expanded interpolation syntax into an ordered list
      # of literal and value pieces. Tango owns the structural operation from
      # here onward; no format string or target formatting policy enters NIR.
      class Interpolation < Expr
        getter pieces : Array(Expr)

        def initialize(id : NodeId, @pieces : Array(Expr), type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end
    end
  end
end
