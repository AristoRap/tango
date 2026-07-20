module Tango
  module IR
    module NIR
      abstract class Literal < Expr
      end

      class IntLiteral < Literal
        getter value : String

        def initialize(id : NodeId, @value : String, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      class FloatLiteral < Literal
        getter value : String

        def initialize(id : NodeId, @value : String, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      class StringLiteral < Literal
        getter value : String

        def initialize(id : NodeId, @value : String, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      class BoolLiteral < Literal
        getter value : Bool

        def initialize(id : NodeId, @value : Bool, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      # A bare `nil`. Its type is the sentinel `Nil` — a real value, boxed into
      # a carrier or spelled as Go `nil` depending on the slot it flows into.
      class NilLiteral < Literal
        def initialize(id : NodeId, span : Source::Range?)
          super(id, IR::Type::NIL, span)
        end
      end
    end
  end
end
