module Tango
  module IR
    module NIR
      abstract class HashExpr < Expr
        getter hash_type : IR::Type

        def initialize(id : NodeId, @hash_type : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end

        def key_type : IR::Type
          hash_type.key_type || IR::Type.unknown
        end

        def value_type : IR::Type
          hash_type.value_type || IR::Type.unknown
        end
      end

      class HashNew < HashExpr
        def initialize(id : NodeId, hash_type : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, hash_type, type, span, method_site)
        end
      end

      class HashGet < HashExpr
        getter hash : Expr
        getter key : Expr

        def initialize(id : NodeId, @hash : Expr, @key : Expr, hash_type : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, hash_type, type, span, method_site)
        end
      end

      class HashSet < HashExpr
        getter hash : Expr
        getter key : Expr
        getter value : Expr

        def initialize(id : NodeId, @hash : Expr, @key : Expr, @value : Expr, hash_type : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, hash_type, type, span, method_site)
        end
      end

      class HashFetch < HashExpr
        getter hash : Expr
        getter key : Expr
        getter default : Expr

        def initialize(id : NodeId, @hash : Expr, @key : Expr, @default : Expr, hash_type : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, hash_type, type, span, method_site)
        end
      end

      class HashHasKey < HashExpr
        getter hash : Expr
        getter key : Expr

        def initialize(id : NodeId, @hash : Expr, @key : Expr, hash_type : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, hash_type, type, span, method_site)
        end
      end

      class HashKeyAt < HashExpr
        getter hash : Expr
        getter index : Expr

        def initialize(id : NodeId, @hash : Expr, @index : Expr, hash_type : IR::Type, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, hash_type, type, span, method_site)
        end
      end
    end
  end
end
