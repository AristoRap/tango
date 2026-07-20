module Tango
  module IR
    module NIR
      # One semantic instance-variable initializer, evaluated after allocation
      # and before `initialize`. Keeping the field identity beside its value
      # makes the source default visible without duplicating name/type fields.
      class FieldInitializer < Stmt
        getter field : IR::Field
        getter value : Expr
        getter name_span : Source::Range?

        def initialize(id : NodeId, @field : IR::Field, @value : Expr, span : Source::Range?, @name_span : Source::Range? = nil)
          super(id, span)
        end

        def name : String
          field.name
        end

        def type : IR::Type
          field.type
        end
      end

      class Class < Stmt
        getter name : String
        getter concrete_type : IR::Type
        getter superclass_name : String?
        getter superclass_type : IR::Type?
        getter fields : Array(IR::Field)
        getter initializers : Array(FieldInitializer)
        getter? reference : Bool
        getter name_span : Source::Range?

        def initialize(id : NodeId, @name : String, @superclass_name : String?, @fields : Array(IR::Field), span : Source::Range?, @name_span : Source::Range? = nil, @reference : Bool = true, @initializers : Array(FieldInitializer) = [] of FieldInitializer, @concrete_type : IR::Type = IR::Type.klass(name), @superclass_type : IR::Type? = nil)
          super(id, span)
        end

        def layout_identity : String
          concrete_type.to_s
        end

        def field?(field_name : String) : IR::Field?
          @fields.find { |field| field.name == field_name }
        end
      end
    end
  end
end
