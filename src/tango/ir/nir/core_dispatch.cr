module Tango
  module IR
    module NIR
      class Not < Expr
        getter value : Expr

        def initialize(id : NodeId, @value : Expr, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      class TypeTest < Expr
        getter value : Expr
        getter target : IR::Type

        def initialize(id : NodeId, @value : Expr, @target : IR::Type, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      class Cast < Expr
        getter value : Expr
        getter target : IR::Type

        def initialize(id : NodeId, @value : Expr, @target : IR::Type, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end
    end
  end
end
