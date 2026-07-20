module Tango
  module IR
    module NIR
      # A `while` has no value-producing form — unlike `If`, it never yields a
      # value, so `While` is a plain `Stmt`, never an `Expr`.
      class While < Stmt
        getter cond : Expr
        getter body : Block

        def initialize(id : NodeId, @cond : Expr, @body : Block, span : Source::Range?)
          super(id, span)
        end
      end
    end
  end
end
