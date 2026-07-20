module Tango
  module IR
    module NIR
      # One semantic cardinality operation for every already-resolved Sized
      # receiver. The receiver type retains whether this means array elements,
      # hash entries, or String code points; planning chooses the realization.
      class Size < Expr
        getter value : Expr

        def initialize(id : NodeId, @value : Expr, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      # A semantic operation retains the complete Crystal-resolved ordinary
      # call as its language-level oracle and conservative fallback.
      # The fallback is data owned by this node rather than a structural child:
      # its arguments and block form the semantic graph, while its call target
      # remains available to call analysis and fallback lowering under this
      # node's existing identity.
      abstract class SemanticOperation < Expr
        getter fallback : Call

        def initialize(@fallback : Call)
          super(fallback.id, fallback.type, fallback.span, fallback.method_site)
        end
      end

      abstract class SemanticCollectionOperation < SemanticOperation
        def source : Expr
          fallback.args.first? || raise ArgumentError.new("semantic collection operation has no receiver")
        end

        def block : BlockLiteral
          fallback.block || raise ArgumentError.new("semantic collection operation has no block")
        end
      end

      class CollectionMap < SemanticCollectionOperation
      end

      class CollectionFilter < SemanticCollectionOperation
        enum Mode
          Keep
          Reject
        end

        getter mode : Mode

        def initialize(fallback : Call, @mode : Mode)
          super(fallback)
        end
      end

      class CollectionEach < SemanticCollectionOperation
      end

      class CollectionFold < SemanticCollectionOperation
        def initial : Expr
          fallback.args[1]? || raise ArgumentError.new("semantic collection fold has no initial value")
        end
      end

      # Shared semantic shapes for public indexed access. Their retained calls
      # keep the ordinary Indexable bodies as the current conservative plan;
      # later indexed traversal can commit a different LIR mechanism without
      # rediscovering method names or concrete collection classes.
      abstract class IndexedOperation < SemanticOperation
        def source : Expr
          fallback.args.first? || raise ArgumentError.new("indexed operation has no receiver")
        end

        def index : Expr
          fallback.args[1]? || raise ArgumentError.new("indexed operation has no index")
        end
      end

      class IndexedRead < IndexedOperation
      end

      class IndexedWrite < IndexedOperation
        def value : Expr
          fallback.args[2]? || raise ArgumentError.new("indexed write has no value")
        end
      end
    end
  end
end
