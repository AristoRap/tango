module Tango
  module IR
    module NIR
      # One source-owned namespace segment. `path` is the complete segmented
      # identity at this declaration; children remain nested in `body` so
      # ownership is structural rather than reconstructed from a flat name.
      class Namespace < Stmt
        getter path : Array(String)
        getter body : Block
        getter name_span : Source::Range?

        def initialize(id : NodeId, @path : Array(String), @body : Block, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, span)
        end

        def name : String
          path.last
        end
      end

      # A source alias remains a declaration even though resolved value types
      # use its canonical target. A Tango-written core can therefore recover
      # the declared alias relation without consulting Crystal.
      class TypeAlias < Stmt
        getter path : Array(String)
        getter target : IR::Type
        getter name_span : Source::Range?

        def initialize(id : NodeId, @path : Array(String), @target : IR::Type, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, span)
        end

        def name : String
          path.last
        end
      end

      # One resolved alias occurrence in a type position. Value types remain
      # canonical, while this node preserves the source alias identity needed
      # by hover/navigation and a future Tango-written semantic consumer.
      class TypeAliasReference < Stmt
        getter path : Array(String)
        getter target : IR::Type
        getter name_span : Source::Range?

        def initialize(id : NodeId, @path : Array(String), @target : IR::Type, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, span)
        end

        def name : String
          path.last
        end
      end

      # A language constant owns its resolved value. Lowering may select a
      # target global representation, but the declaration/value relation is
      # complete before planning.
      class Constant < Stmt
        getter path : Array(String)
        getter value : Expr
        getter type : IR::Type
        getter name_span : Source::Range?

        def initialize(id : NodeId, @path : Array(String), @value : Expr, @type : IR::Type, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, span)
        end

        def name : String
          path.last
        end
      end

      # One Crystal-resolved constant occurrence. The segmented owner/name is
      # retained through analysis; no downstream phase reparses `A::B::VALUE`.
      class ConstantReference < Expr
        getter path : Array(String)
        getter name_span : Source::Range?

        def initialize(id : NodeId, @path : Array(String), type : IR::Type?, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, type, span)
        end

        def name : String
          path.last
        end
      end
    end
  end
end
