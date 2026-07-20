module Tango
  module IR
    module NIR
      # A reference to a class's constructor: `T.new(args)`. It keeps the
      # class reference and the source range of the `T` token, so tooling
      # resolves `T` to its declaration. The allocate/initialize/return
      # mechanism is committed in lowering, not spelled here.
      class New < Expr
        getter class_name : String
        getter args : Array(Expr)
        getter name_span : Source::Range?
        getter? invokes_initializer : Bool

        def initialize(id : NodeId, @class_name : String, @args : Array(Expr), type : IR::Type?, span : Source::Range?, @name_span : Source::Range? = nil, method_site : MethodSite? = nil, @invokes_initializer : Bool = true)
          super(id, type, span, method_site)
        end
      end
    end
  end
end
