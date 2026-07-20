module Tango
  module IR
    module NIR
      enum CallableKind
        Function
        InstanceMethod
        ClassMethod
        Initializer
        Constructor
        Proc
      end

      # Uniform metadata for a source-level receiver call, whether it remains a
      # generic Call or the frontend specializes it into an Array/Channel/etc.
      # Tooling consumes this shape and never dispatches on library APIs.
      record MethodSite,
        owner : IR::Type,
        name : String,
        argument_types : Array(IR::Type),
        return_type : IR::Type,
        name_span : Source::Range?,
        kind : CallableKind = CallableKind::InstanceMethod

      # Value-producing NIR node. Its `type` is the structured identity Crystal
      # narrowed for this occurrence — read per-node, never from a variable's
      # declared slot, so `if x` hands the branch's `x` the narrowed member for
      # free.
      abstract class Expr < Stmt
        getter type : IR::Type?
        getter method_site : MethodSite?

        def initialize(id : NodeId, @type : IR::Type?, span : Source::Range?, @method_site : MethodSite? = nil)
          super(id, span)
        end
      end

      abstract class NamedExpr < Expr
        getter name : String
        getter name_span : Source::Range?

        def initialize(id : NodeId, @name : String, type : IR::Type?, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, type, span)
        end
      end

      class Local < NamedExpr
        # Range of the name identifier, so goto-definition lands on the name and
        # a reference resolves to its declaration from anywhere on the word.
      end

      # A compile-time class receiver such as `File` in `File.read`. It is a
      # real source/tooling occurrence but never a runtime call argument.
      class ClassRef < NamedExpr
      end

      class InstanceVar < NamedExpr
        getter owner : String

        def initialize(id : NodeId, name : String, @owner : String, type : IR::Type?, span : Source::Range?, name_span : Source::Range? = nil)
          super(id, name, type, span, name_span)
        end
      end

      class Param < Stmt
        getter name : String
        getter type : IR::Type?
        getter name_span : Source::Range?

        def initialize(id : NodeId, @name : String, @type : IR::Type?, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, span)
        end
      end

      class Assign < Expr
        getter target : Local | InstanceVar
        getter value : Expr

        def initialize(id : NodeId, @target : Local | InstanceVar, @value : Expr, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      class If < Expr
        getter cond : Expr
        getter then_branch : Block
        getter else_branch : Block?

        def initialize(id : NodeId, @cond : Expr, @then_branch : Block, @else_branch : Block?, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end

      class UnsupportedExpr < Expr
        getter crystal_node : String

        def initialize(id : NodeId, @crystal_node : String, type : IR::Type?, span : Source::Range?)
          super(id, type, span)
        end
      end
    end
  end
end
