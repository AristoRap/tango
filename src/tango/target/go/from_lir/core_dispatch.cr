module Tango
  module Target
    module Go
      class FromLIR
        private def translate_type_test(test : Tango::IR::LIR::TypeTest, requirements : Array(Runtime::Requirement)) : IR::Expr
          value = translate_value(test.value, requirements)
          case test.strategy
          in .static_true?     then static_type_test(value, true)
          in .static_false?    then static_type_test(value, false)
          in .pointer_non_nil? then IR::Binary.new(value, "!=", IR::Ident.new("nil"))
          in .pointer_nil?     then IR::Binary.new(value, "==", IR::Ident.new("nil"))
          in .carrier_tag?
            variant = @types.variant(test.source, test.target)
            IR::Binary.new(IR::Selector.new(value, "tag"), "==", IR::IntLit.new(variant.tag.to_s))
          in .carrier_nil?
            IR::Binary.new(IR::Selector.new(value, "tag"), "==", IR::IntLit.new(@types.nil_tag(test.source).to_s))
          end
        end

        private def static_type_test(value : IR::Expr, result : Bool) : IR::Expr
          body = [
            IR::AssignStmt.new(IR::Ident.new("_"), IR::AssignStmt::Mode::Reassign, value).as(IR::Stmt),
            IR::ReturnStmt.new(IR::BoolLit.new(result)).as(IR::Stmt),
          ]
          IR::Call.new(IR::FuncLit.new([] of IR::Param, "bool", body), [] of IR::Expr)
        end

        private def translate_cast(cast : Tango::IR::LIR::Cast, requirements : Array(Runtime::Requirement)) : IR::Expr
          return translate_value(cast.value, requirements) if cast.strategy.passthrough?

          requirements << Runtime::Helper.new("tangoCastFail")
          base = IR::Ident.new("__cast")
          body = [IR::AssignStmt.new(base, IR::AssignStmt::Mode::Declare, translate_value(cast.value, requirements)).as(IR::Stmt)]
          result = base.as(IR::Expr)
          failed = if cast.strategy.pointer_checked?
                     IR::Binary.new(base, "==", IR::Ident.new("nil")).as(IR::Expr)
                   else
                     variant = @types.variant(cast.source, cast.target)
                     result = IR::Selector.new(base, "v#{variant.label}")
                     IR::Binary.new(IR::Selector.new(base, "tag"), "!=", IR::IntLit.new(variant.tag.to_s)).as(IR::Expr)
                   end
          body << IR::IfStmt.new(
            failed,
            [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("tangoCastFail"), [IR::StringLit.new(cast_message(cast)).as(IR::Expr)])).as(IR::Stmt)],
            [] of IR::Stmt
          )
          body << IR::ReturnStmt.new(result)
          IR::Call.new(IR::FuncLit.new([] of IR::Param, go_type(cast.target), body), [] of IR::Expr)
        end

        private def cast_message(cast : Tango::IR::LIR::Cast) : String
          prefix = cast.loc.try { |loc| "#{loc.file}:#{loc.line}:#{loc.column}: " } || ""
          "#{prefix}cast from #{cast.source} to #{cast.target} failed"
        end
      end
    end
  end
end
