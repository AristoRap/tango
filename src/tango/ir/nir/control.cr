module Tango
  module IR
    module NIR
      abstract class ControlExit < Stmt
        getter value : Expr?
        getter target : NodeId?

        def initialize(id : NodeId, @value : Expr?, @target : NodeId?, span : Source::Range?)
          super(id, span)
        end
      end

      class Return < ControlExit
        def initialize(id : NodeId, value : Expr?, target : NodeId?, span : Source::Range?)
          super(id, value, target, span)
        end
      end

      class Break < ControlExit
        def initialize(id : NodeId, value : Expr?, target : NodeId?, span : Source::Range?)
          super(id, value, target, span)
        end
      end

      class Next < ControlExit
        def initialize(id : NodeId, value : Expr?, target : NodeId?, span : Source::Range?)
          super(id, value, target, span)
        end
      end
    end
  end
end
