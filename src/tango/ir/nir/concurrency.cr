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

        def initialize(id : NodeId, @element : IR::Type, @capacity : Expr?, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      # `Mutex.new` after the prelude forwards to the `:tango_mutex_new`
      # primitive. Carries nothing structural — a mutex has a single native
      # representation, chosen and spelled entirely at the target.
      class MutexNew < Expr
        def initialize(id : NodeId, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      # The target-neutral data common to a direct channel operation and a
      # select arm. Keeping the operation as one composed value means syntax
      # families can grow without copying channel/value/element/kind state
      # between their owners.
      class ChannelOperation
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

        def initialize(@kind : Kind, @channel : Expr, @value : Expr?, @element : IR::Type)
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
          getter operation : ChannelOperation
          getter captured : Local?
          getter body : Block

          def initialize(kind : ChannelOperation::Kind, channel : Expr, value : Expr?, @captured : Local?, element : IR::Type, @body : Block)
            @operation = ChannelOperation.new(kind, channel, value, element)
          end

          def kind : ChannelOperation::Kind
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

      # A native channel operation on `channel`, tagged by kind. `send` carries
      # its `value`; `receive`/`receive?`/`close` do not. `element` is the
      # channel's `T`, kept so lowering/target need no receiver-type lookup.
      class ChannelOp < Expr
        alias Kind = ChannelOperation::Kind

        getter operation : ChannelOperation

        def initialize(id : NodeId, kind : Kind, channel : Expr, value : Expr?, element : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          @operation = ChannelOperation.new(kind, channel, value, element)
          super(id, type, span, method_site)
        end

        def kind : Kind
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
    end
  end
end
