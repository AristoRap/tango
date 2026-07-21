module Tango
  module IR
    module NIR
      # Array operations are structured at the frontend boundary. Crystal has
      # already expanded literals and inferred T; these nodes retain that
      # element type without leaking the expansion or a target representation.
      class ArrayNew < Expr
        getter element : IR::Type

        def initialize(id : NodeId, @element : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      class ArrayBuild < Expr
        getter element : IR::Type
        getter size : Expr

        def initialize(id : NodeId, @element : IR::Type, @size : Expr, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      # Shared receiver and element-type state for operations on an existing
      # Array(T). Concrete operations retain their own operands and semantics.
      abstract class ArrayOperation < Expr
        getter array : Expr
        getter element : IR::Type

        def initialize(id : NodeId, @array : Expr, @element : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      class ArrayGet < ArrayOperation
        getter index : Expr

        def initialize(id : NodeId, array : Expr, @index : Expr, element : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, array, element, type, span, method_site)
        end
      end

      class ArraySet < ArrayOperation
        getter index : Expr
        getter value : Expr

        def initialize(id : NodeId, array : Expr, @index : Expr, @value : Expr, element : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, array, element, type, span, method_site)
        end
      end

      class ArrayPush < ArrayOperation
        getter value : Expr

        def initialize(id : NodeId, array : Expr, @value : Expr, element : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, array, element, type, span, method_site)
        end
      end

      # A value-producing expression sequence. Crystal uses this shape for an
      # expanded non-empty array literal (build, obtain buffer, indexed writes,
      # final array temp). Keeping it structured lets every inner array
      # primitive traverse the ordinary pipeline.
      class ValueSequence < Expr
        getter prefix : Block
        getter value : Expr

        def initialize(id : NodeId, @prefix : Block, @value : Expr, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end
    end
  end
end
