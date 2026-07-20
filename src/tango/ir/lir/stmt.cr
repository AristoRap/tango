module Tango
  module IR
    module LIR
      abstract class Stmt
        getter loc : SourceLoc?

        def initialize(@loc : SourceLoc? = nil)
        end
      end

      # `ch <- value`.
      class ChanSend < Stmt
        getter channel : Value
        getter value : Value

        def initialize(@channel : Value, @value : Value, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      # `close(ch)`.
      class ChanClose < Stmt
        getter channel : Value

        def initialize(@channel : Value, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      # `go proc()` — launch `proc` in a goroutine.
      class Spawn < Stmt
        getter proc : Value

        def initialize(@proc : Value, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      # `String#each_char`. The callback is a normal lowered closure; its
      # return type is the existing block plan's committed plain or protocol
      # shape, not an iteration decision rediscovered by the target.
      class StringEachChar < Stmt
        getter string : Value
        getter block : Closure

        def initialize(@string : Value, @block : Closure, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      # A native multi-way channel wait. Each arm is one Go comm clause plus its
      # body; a receive arm binds the received value (via `binding`) and is
      # closed-checked (`element` types the receive). `default` present means a
      # non-blocking select (Go `default:`); absent means blocking.
      class Select < Stmt
        class Arm
          enum Kind
            Receive
            ReceiveMaybePointer
            ReceiveMaybeCarrier
            Send
          end

          getter kind : Kind
          getter channel : Value
          getter value : Value?
          getter binding : String?
          getter element : IR::Type
          getter result_type : IR::Type?
          getter body : Array(Stmt)

          def initialize(@kind : Kind, @channel : Value, @value : Value?, @binding : String?, @element : IR::Type, @body : Array(Stmt), @result_type : IR::Type? = nil)
          end
        end

        getter arms : Array(Arm)
        getter default : Array(Stmt)?

        def initialize(@arms : Array(Arm), @default : Array(Stmt)? = nil, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      class FieldAssign < Stmt
        getter receiver : Value
        getter field : String
        getter value : Value

        def initialize(@receiver : Value, @field : String, @value : Value, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      class ExternalCall < Stmt
        getter target : ExternalTarget
        getter args : Array(Value)

        def initialize(@target : ExternalTarget, @args : Array(Value), loc : SourceLoc? = nil)
          super(loc)
        end
      end

      class UnsupportedStmt < Stmt
        getter reason : String

        def initialize(@reason : String, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      class Assign < Stmt
        enum Mode
          Declare
          Reassign
        end

        getter target : String
        getter value : Value
        getter mode : Mode

        def initialize(@target : String, @value : Value, @mode : Mode, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      class Discard < Stmt
        getter value : Value

        def initialize(@value : Value, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      class If < Stmt
        getter cond : Value
        getter then_body : Array(Stmt)
        getter else_body : Array(Stmt)

        def initialize(@cond : Value, @then_body : Array(Stmt), @else_body : Array(Stmt), loc : SourceLoc? = nil)
          super(loc)
        end
      end

      class While < Stmt
        getter cond : Value
        getter body : Array(Stmt)
        getter target : String?

        def initialize(@cond : Value, @body : Array(Stmt), loc : SourceLoc? = nil, @target : String? = nil)
          super(loc)
        end
      end

      class Handler < Stmt
        getter body : Array(Stmt)
        getter clauses : Array(RescueClause(Array(Stmt)))
        getter else_body : Array(Stmt)?
        getter ensure_body : Array(Stmt)?
        getter? no_return : Bool

        def initialize(@body : Array(Stmt), @clauses : Array(RescueClause(Array(Stmt))), @else_body : Array(Stmt)?, @ensure_body : Array(Stmt)?, @no_return : Bool = false, loc : SourceLoc? = nil)
          super(loc)
        end
      end

      class AbruptExit < Stmt
        enum Shape
          Return
          Break
          Next
          RaiseMessage
          RaiseException
        end

        getter shape : Shape
        getter value : Value?
        getter target : String?

        def initialize(@shape : Shape, @value : Value?, loc : SourceLoc? = nil, @target : String? = nil)
          super(loc)
        end
      end
    end
  end
end
