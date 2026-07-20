module Tango
  module IR
    module NIR
      # A source-owned nominal enum declaration. Member values retain the
      # frontend-resolved integer spelling, while each name range gives editor
      # consumers a real declaration token rather than a reconstructed path.
      class Enum < Stmt
        record Member, name : String, value : String, name_span : Source::Range?

        getter type : IR::Type
        getter base_type : IR::Type
        getter members : Array(Member)
        getter name_span : Source::Range?

        def initialize(id : NodeId, @type : IR::Type, @base_type : IR::Type, @members : Array(Member), span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, span)
        end

        def name : String
          type.name || type.to_s
        end
      end

      # One resolved enum constant occurrence. The owner/member pair remains
      # structured through lowering; no phase reparses `State::Idle`.
      class EnumMember < Expr
        getter enum_type : IR::Type
        getter name : String
        getter name_span : Source::Range?

        def initialize(id : NodeId, @enum_type : IR::Type, @name : String, type : IR::Type?, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, type, span)
        end
      end
    end
  end
end
