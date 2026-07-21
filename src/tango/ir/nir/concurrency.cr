module Tango
  module IR
    module NIR
      # `spawn { … }` after the prelude forwards its block to the `:tango_go`
      # primitive: a goroutine launch running `proc`. An Expr (typed Nil) like
      # every other executable NIR node, so it slots into a def body uniformly.
      class Spawn < Expr
        getter proc : Expr

        def initialize(id : NodeId, @proc : Expr, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      # `Channel(T).new` / `Channel(T).new(capacity)`. Keeps the element type
      # structurally (never re-parsed from a name) so the target spells `chan T`.
      class ChannelNew < Expr
        getter element : IR::Type
        getter capacity : Expr?

        def initialize(id : NodeId, @element : IR::Type, @capacity : Expr?, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      # `Mutex.new` after the prelude forwards to the `:tango_mutex_new`
      # primitive. Carries nothing structural — a mutex has a single native
      # representation, chosen and spelled entirely at the target.
      class MutexNew < Expr
        def initialize(id : NodeId, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      # One resolved channel-method expression, used unchanged in ordinary
      # expression position and as a select arm's operation. Keeping select
      # operations as real Expr nodes preserves their identity, source span,
      # type, and method site for every downstream consumer.
      class ChannelOp < Expr
        enum Kind
          Send
          Receive
          ReceiveMaybe
          NextState
          Close
        end

        getter kind : Kind
        getter channel : Expr
        getter value : Expr?
        getter element : IR::Type

        def initialize(id : NodeId, @kind : Kind, @channel : Expr, @value : Expr?, @element : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      # A native multi-way channel wait. Crystal expands the `select` keyword into
      # `Channel.select`-plumbing + an if-chain; the frontend recognizes that shape
      # and folds it back to this node, so the `__temp`/index/if-chain never reach
      # analysis. Each arm holds its own body and (for a receive-assign) the local
      # it binds, so every arm lowers to one Go `case` with its own scoped value —
      # no shared value carrier. `else_body` present means a non-blocking select.
      class Select < Expr
        # One `when` of a `select`. A receive arm may bind `captured` (the
        # `x` of `when x = ch.receive`); a send arm carries its `value`.
        class Arm
          getter operation : ChannelOp
          getter captured : Local?
          getter body : Block

          def initialize(@operation : ChannelOp, @captured : Local?, @body : Block)
          end

          def kind : ChannelOp::Kind
            operation.kind
          end

          def channel : Expr
            operation.channel
          end

          def value : Expr?
            operation.value
          end

          def element : IR::Type
            operation.element
          end
        end

        getter arms : Array(Arm)
        getter else_body : Block?

        def initialize(id : NodeId, @arms : Array(Arm), @else_body : Block?, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end
    end
  end
end
