module Tango
  module Target
    module Go
      class FromLIR
        # A carrier lowers to a Go struct `{tag uint8; v<label> T; …}` — the Nil
        # variant contributes only the tag because its zero value is nil.
        private def carrier_struct(union : Tango::IR::LIR::UnionType) : IR::StructDecl
          fields = [IR::StructDecl::Field.new("tag", "uint8")]
          union.variants.each do |variant|
            variant.payload.try { |payload| fields << IR::StructDecl::Field.new("v#{variant.label}", go_type(payload)) }
          end
          IR::StructDecl.new(union.name, fields)
        end

        # fmt recognizes String() through its native Stringer contract. Each
        # planned variant becomes one typed switch case over the committed tag;
        # no target-side type relation or strategy is reconstructed here.
        private def carrier_string_method(union : Tango::IR::LIR::UnionType, requirements : Array(Runtime::Requirement)) : IR::MethodDecl
          requirements << Runtime::Import.new("fmt")
          receiver = IR::Func::Receiver.new("value", union.name)
          cases = union.variants.map do |variant|
            result = if variant.payload
                       payload = IR::Selector.new(IR::Ident.new(receiver.name), "v#{variant.label}")
                       IR::Call.new(IR::Selector.new(IR::Ident.new("fmt"), "Sprint"), [payload.as(IR::Expr)] of IR::Expr)
                     else
                       IR::StringLit.new("").as(IR::Expr)
                     end
            IR::Switch::Case.new(
              IR::IntLit.new(variant.tag.to_s),
              [IR::ReturnStmt.new(result).as(IR::Stmt)]
            )
          end
          cases << IR::Switch::Case.new(
            nil,
            [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [IR::StringLit.new("invalid #{union.name} tag").as(IR::Expr)])).as(IR::Stmt)]
          )
          body = [IR::Switch.new(IR::Selector.new(IR::Ident.new(receiver.name), "tag"), cases).as(IR::Stmt)]
          IR::MethodDecl.new("String", receiver, body, "string")
        end

        # The conversion's source/target names, tags, and payload labels are
        # already committed in LIR. This is deliberately mechanical typed-IR
        # assembly: one switch case per planned source variant.
        private def carrier_conversion_func(conversion : Tango::IR::LIR::UnionConversion) : IR::Func
          mapping = conversion.mapping
          value = IR::Ident.new("value")
          cases = mapping.variants.map do |variant|
            fields = [
              {"tag", IR::IntLit.new(variant.target_tag.to_s).as(IR::Expr)},
            ] of Tuple(String, IR::Expr)
            if source_label = variant.source_label
              target_label = variant.target_label || raise "payload conversion without target payload label"
              payload = IR::Selector.new(value, "v#{source_label}")
              fields << {"v#{target_label}", payload.as(IR::Expr)}
            end
            result = IR::CompositeLit.new(mapping.target_name, fields)
            IR::Switch::Case.new(
              IR::IntLit.new(variant.source_tag.to_s),
              [IR::ReturnStmt.new(result).as(IR::Stmt)]
            )
          end
          cases << IR::Switch::Case.new(
            nil,
            [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [IR::StringLit.new("invalid #{mapping.source_name} tag").as(IR::Expr)])).as(IR::Stmt)]
          )
          body = [IR::Switch.new(IR::Selector.new(value, "tag"), cases).as(IR::Stmt)]
          IR::Func.new(
            mapping.name,
            body,
            [IR::Param.new("value", mapping.source_name)],
            mapping.target_name
          )
        end
      end
    end
  end
end
