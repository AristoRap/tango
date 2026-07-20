module Tango
  module Target
    module Go
      class FromLIR
        # Spells the source/transform/terminal composition already committed in
        # LIR. Eligibility and profile policy are intentionally absent here.
        private def translate_fused_collection(value : Tango::IR::LIR::FusedCollectionTraversal, requirements : Array(Runtime::Requirement)) : IR::Expr
          if terminal = value.terminal.as?(Tango::IR::LIR::CollectionEachTerminal)
            return translate_string_segment_each(value, terminal, requirements)
          end

          source = value.source.as?(Tango::IR::LIR::ArrayElements) || raise "unsupported fused collection source #{value.source.class.name}"
          terminal = value.terminal.as?(Tango::IR::LIR::CollectionFoldTerminal) || raise "unsupported fused collection terminal #{value.terminal.class.name}"
          source_name = @names.temp("source")
          element_name = @names.temp("element")
          accumulator_name = @names.temp("fold")

          body = [
            IR::AssignStmt.new(
              IR::Ident.new(source_name),
              IR::AssignStmt::Mode::Declare,
              translate_value(source.value, requirements)
            ).as(IR::Stmt),
          ]

          body << IR::AssignStmt.new(
            IR::Ident.new(accumulator_name),
            IR::AssignStmt::Mode::Declare,
            translate_value(terminal.initial, requirements)
          ).as(IR::Stmt)

          loop_body = [] of IR::Stmt
          current = IR::Ident.new(element_name).as(IR::Expr)
          value.transforms.each do |transform|
            # Keep the typed closure literal at the call site. Binding it to a
            # function-valued temporary would hide the body from Go's inliner
            # and turn every element into an indirect call.
            callee = translate_value(transform.block, requirements)
            invocation = IR::Call.new(callee, [current] of IR::Expr)
            case transform
            when Tango::IR::LIR::CollectionFilterTransform
              loop_body << IR::IfStmt.new(
                IR::Not.new(invocation),
                [IR::BranchStmt.new(IR::BranchStmt::Kind::Continue).as(IR::Stmt)],
                [] of IR::Stmt
              )
            when Tango::IR::LIR::CollectionMapTransform
              mapped = @names.temp("mapped")
              loop_body << IR::AssignStmt.new(
                IR::Ident.new(mapped),
                IR::AssignStmt::Mode::Declare,
                invocation
              )
              current = IR::Ident.new(mapped)
            else
              raise "unsupported fused collection transform #{transform.class.name}"
            end
          end

          folded = IR::Call.new(
            translate_value(terminal.block, requirements),
            [IR::Ident.new(accumulator_name).as(IR::Expr), current] of IR::Expr
          )
          loop_body << IR::AssignStmt.new(
            IR::Ident.new(accumulator_name),
            IR::AssignStmt::Mode::Reassign,
            folded
          )

          source_expr = IR::Ident.new(source_name).as(IR::Expr)
          source_expr = IR::Deref.new(source_expr) if @types.array_reference?(source.element)
          body << IR::RangeStmt.new(element_name, source_expr, loop_body)
          body << IR::ReturnStmt.new(IR::Ident.new(accumulator_name))

          closure = IR::FuncLit.new([] of IR::Param, go_type(value.type), body)
          IR::Call.new(closure, [] of IR::Expr)
        end

        private def translate_string_segment_each(value : Tango::IR::LIR::FusedCollectionTraversal, terminal : Tango::IR::LIR::CollectionEachTerminal, requirements : Array(Runtime::Requirement)) : IR::Expr
          source = value.source.as?(Tango::IR::LIR::StringSegments) || raise "unsupported each source #{value.source.class.name}"
          raise "string segment each unexpectedly has transforms" unless value.transforms.empty?
          helper = terminal.block.return_type == Tango::IR::Type.bool ? "tangoStringSplitEachBreak" : "tangoStringSplitEach"
          requirements << Runtime::Helper.new(helper)
          IR::Call.new(IR::Ident.new(helper), [
            translate_value(source.value, requirements),
            translate_value(source.separator, requirements),
            translate_value(terminal.block, requirements),
          ] of IR::Expr)
        end
      end
    end
  end
end
