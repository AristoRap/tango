module Tango
  module IR
    module NIR
      # Every String character operation shares the semantic string receiver.
      # Its unit is fixed as Unicode code points; no target representation
      # leaks across this frontend-neutral boundary.
      abstract class StringOperation < Expr
        getter string : Expr

        def initialize(id : NodeId, @string : Expr, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      class StringCharAt < StringOperation
        getter index : Expr

        def initialize(id : NodeId, string : Expr, @index : Expr, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, string, type, span, method_site)
        end
      end

      # `each_char` owns the iteration semantics while retaining the ordinary
      # typed block. Analysis records captures; planning selects the established
      # break/next protocol; lowering commits the loop operation.
      class StringEachChar < StringOperation
        getter block : BlockLiteral

        def initialize(id : NodeId, string : Expr, @block : BlockLiteral, type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, string, type, span, method_site)
        end
      end

      # Tango's whitespace or exact-separator split operation. Its result
      # remains a structured Array(String); target library selection and array
      # representation stay downstream of this language node.
      class StringSplit < Expr
        getter string : Expr
        getter separator : Expr?

        def initialize(id : NodeId, @string : Expr, type : IR::Type?, span : Source::Range?, @separator : Expr? = nil, method_site : MethodSite? = nil)
          super(id, type, span, method_site)
        end
      end

      # Decimal parsing remains visible as a language operation so the target
      # cannot silently choose its own malformed-input or exception behavior.
      class StringToFloat < StringOperation
      end

      # One Crystal-shaped integer parse operation across every supported
      # signed/unsigned width. The six explicit option expressions retain
      # evaluation order and keep parsing policy out of the target.
      class StringToInteger < StringOperation
        getter options : Array(Expr)

        def initialize(id : NodeId, string : Expr, @options : Array(Expr), type : IR::Type?, span : Source::Range?, method_site : MethodSite? = nil)
          super(id, string, type, span, method_site)
        end
      end
    end
  end
end
