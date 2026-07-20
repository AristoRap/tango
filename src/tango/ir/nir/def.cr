module Tango
  module IR
    module NIR
      class Def < Stmt
        getter name : String
        getter owner : IR::Type?
        getter callable_kind : CallableKind
        getter params : Array(Param)
        getter block_param : BlockParam?
        getter body : Block
        getter return_type : IR::Type?
        # Range of the def name identifier, so goto-definition lands on the
        # name rather than the `def` keyword. Nil when unavailable.
        getter name_span : Source::Range?
        getter capability_witnesses : Array(IR::CapabilityConformance)

        def initialize(id : NodeId, @name : String, @params : Array(Param), @body : Block, @return_type : IR::Type?, span : Source::Range?, @block_param : BlockParam? = nil, @name_span : Source::Range? = nil, @owner : IR::Type? = nil, @callable_kind : CallableKind = CallableKind::Function, @capability_witnesses : Array(IR::CapabilityConformance) = [] of IR::CapabilityConformance)
          super(id, span)
        end
      end
    end
  end
end
