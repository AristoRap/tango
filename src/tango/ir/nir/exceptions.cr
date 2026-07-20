module Tango
  module IR
    module NIR
      # A typed language raise. The frontend has already resolved which prelude
      # overload won, so lowering never has to rediscover message-vs-exception.
      class Raise < Expr
        enum Kind
          Message
          Exception
        end

        getter value : Expr
        getter kind : Kind

        def initialize(id : NodeId, @value : Expr, @kind : Kind, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      class ExceptionNew < Expr
        getter class_name : String
        getter message : Expr?

        def initialize(id : NodeId, @class_name : String, @message : Expr?, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      # One source rescue clause. An empty type list is the catch-all form;
      # otherwise Crystal has already resolved every path to a concrete type.
      class RescueClause
        getter types : Array(IR::Type)
        getter binding : Local?
        getter body : Block

        def initialize(@types : Array(IR::Type), @binding : Local?, @body : Block)
        end

        def catch_all? : Bool
          types.empty?
        end
      end

      # begin/rescue/else/ensure remains an expression in NIR because Crystal
      # permits it in value position. The statement consumer is the
      # first lowering; retaining the resolved type prevents a future value
      # consumer from returning to the frontend AST.
      class ExceptionHandler < Expr
        getter body : Block
        getter clauses : Array(RescueClause)
        getter else_branch : Block?
        getter ensure_branch : Block?

        def initialize(id : NodeId, @body : Block, @clauses : Array(RescueClause), @else_branch : Block?, @ensure_branch : Block?, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end
    end
  end
end
