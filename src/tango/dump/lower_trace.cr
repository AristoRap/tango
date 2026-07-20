module Tango
  module Dump
    module LowerTrace
      def self.render_nir(snapshot : Compiler::Snapshot) : String
        program = snapshot.nir
        plans = snapshot.plans
        return "" unless program && plans

        String.build do |io|
          IR::NIR::Walk.children(program).each do |stmt|
            case stmt
            when IR::NIR::Def
              emit_nir_def(io, stmt, plans)
            else
              emit_nir_stmt(io, stmt, plans)
            end
          end
        end
      end

      def self.render_lir(snapshot : Compiler::Snapshot) : String
        program = snapshot.lir
        return "" unless program

        String.build do |io|
          program.functions.each { |function| emit_lir_func(io, function) }
          program.body.each { |stmt| emit_lir_stmt(io, stmt, 0) }
        end
      end

      private def self.emit_nir_def(io : IO, node : IR::NIR::Def, plans : Planning::Plans::Table) : Nil
        plan = plans.monomorphs[node.id]?
        io << "(def"
        attr(io, "id", node.id.to_s)
        attr(io, "name", node.name)
        attr(io, "lowered", plan.try(&.name) || node.name)
        attr(io, "return", type_name(node.return_type))
        io << '\n'
        node.params.each { |param| emit_nir_param(io, param, 1) }
        emit_nir_block(io, node.body, plans, 1)
        io << ")\n"
      end

      private def self.emit_nir_stmt(io : IO, node : IR::NIR::Stmt, plans : Planning::Plans::Table, depth : Int32 = 0) : Nil
        if node.is_a?(IR::NIR::Expr) && !node.is_a?(IR::NIR::Assign) && !node.is_a?(IR::NIR::Call) && !node.is_a?(IR::NIR::If)
          emit_nir_expr(io, node, plans, depth)
          return
        end

        indent(io, depth)
        case node
        when IR::NIR::Call
          emit_nir_call_head(io, node, plans)
          if node.args.empty? && node.block.nil?
            io << ")\n"
          else
            io << '\n'
            node.args.each { |arg| emit_nir_expr(io, arg, plans, depth + 1) }
            node.block.try { |block| emit_nir_expr(io, block, plans, depth + 1) }
            indent(io, depth)
            io << ")\n"
          end
        when IR::NIR::Assign
          io << "(assign"
          attr(io, "id", node.id.to_s)
          attr(io, "target", assign_target_name(node.target))
          attr(io, "type", type_name(node.type))
          io << '\n'
          emit_nir_expr(io, node.value, plans, depth + 1)
          indent(io, depth)
          io << ")\n"
        when IR::NIR::If
          emit_nir_if(io, node, plans, depth)
        when IR::NIR::Return
          io << "(return"
          attr(io, "id", node.id.to_s)
          node.value.try do |value|
            io << '\n'
            emit_nir_expr(io, value, plans, depth + 1)
            indent(io, depth)
          end
          io << ")\n"
        when IR::NIR::Expr
          emit_nir_expr(io, node, plans, depth)
        else
          io << '(' << node.class.name.split("::").last.underscore
          attr(io, "id", node.id.to_s)
          emit_nir_children(io, node, plans, depth)
        end
      end

      private def self.emit_nir_expr(io : IO, node : IR::NIR::Expr, plans : Planning::Plans::Table, depth : Int32) : Nil
        indent(io, depth)
        case node
        when IR::NIR::IntLiteral
          io << "(int"
          attr(io, "id", node.id.to_s)
          attr(io, "type", type_name(node.type))
          attr(io, "value", node.value)
          io << ")\n"
        when IR::NIR::FloatLiteral
          io << "(float"
          attr(io, "id", node.id.to_s)
          attr(io, "type", type_name(node.type))
          attr(io, "value", node.value)
          io << ")\n"
        when IR::NIR::StringLiteral
          io << "(string"
          attr(io, "id", node.id.to_s)
          attr(io, "type", type_name(node.type))
          attr(io, "value", node.value)
          io << ")\n"
        when IR::NIR::BoolLiteral
          io << "(bool"
          attr(io, "id", node.id.to_s)
          attr(io, "type", type_name(node.type))
          attr(io, "value", node.value.to_s)
          io << ")\n"
        when IR::NIR::Local
          io << "(local"
          attr(io, "id", node.id.to_s)
          attr(io, "name", node.name)
          attr(io, "type", type_name(node.type))
          io << ")\n"
        when IR::NIR::Call
          emit_nir_call_head(io, node, plans)
          if node.args.empty? && node.block.nil?
            io << ")\n"
          else
            io << '\n'
            node.args.each { |arg| emit_nir_expr(io, arg, plans, depth + 1) }
            node.block.try { |block| emit_nir_expr(io, block, plans, depth + 1) }
            indent(io, depth)
            io << ")\n"
          end
        when IR::NIR::If
          emit_nir_if(io, node, plans, depth)
        when IR::NIR::BlockLiteral
          io << "(block-literal"
          attr(io, "id", node.id.to_s)
          attr(io, "type", type_name(node.type))
          attr(io, "signature", proc_signature(node.signature))
          io << '\n'
          emit_nir_block(io, node.body, plans, depth + 1)
          indent(io, depth)
          io << ")\n"
        else
          io << '(' << node.class.name.split("::").last.underscore
          attr(io, "id", node.id.to_s)
          attr(io, "type", type_name(node.type))
          emit_nir_children(io, node, plans, depth)
        end
      end

      private def self.emit_nir_children(io : IO, node : IR::NIR::Stmt, plans : Planning::Plans::Table, depth : Int32) : Nil
        children = IR::NIR::Walk.children(node)
        if children.empty?
          io << ")\n"
        else
          io << '\n'
          children.each { |child| emit_nir_stmt(io, child, plans, depth + 1) }
          indent(io, depth)
          io << ")\n"
        end
      end

      private def self.emit_nir_call_head(io : IO, node : IR::NIR::Call, plans : Planning::Plans::Table) : Nil
        io << "(call"
        attr(io, "id", node.id.to_s)
        attr(io, "name", node.name)
        attr(io, "type", type_name(node.type))
        case primitive = node.primitive
        when IR::NIR::Primitive
          attr(io, "decision", "primitive:#{primitive.kind}")
          attr(io, "operator", primitive.name)
        else
          case plan = plans.calls[node.id]?
          when Planning::Plans::InternalCall
            attr(io, "decision", "internal-call")
            attr(io, "lowered", plan.name)
          when Planning::Plans::ExternalGo
            attr(io, "decision", "external-go")
            attr(io, "lowered", plan.callee.to_s)
          when Planning::Plans::UnsupportedCall
            attr(io, "decision", "unsupported-call")
          else
            attr(io, "decision", "unplanned")
          end
        end
      end

      private def self.emit_nir_if(io : IO, node : IR::NIR::If, plans : Planning::Plans::Table, depth : Int32) : Nil
        io << "(if"
        attr(io, "id", node.id.to_s)
        attr(io, "type", type_name(node.type))
        io << '\n'
        emit_nir_expr(io, node.cond, plans, depth + 1)
        emit_nir_block(io, node.then_branch, plans, depth + 1)
        node.else_branch.try { |branch| emit_nir_block(io, branch, plans, depth + 1) }
        indent(io, depth)
        io << ")\n"
      end

      private def self.emit_nir_param(io : IO, node : IR::NIR::Param, depth : Int32) : Nil
        indent(io, depth)
        io << "(param"
        attr(io, "id", node.id.to_s)
        attr(io, "name", node.name)
        attr(io, "type", type_name(node.type))
        io << ")\n"
      end

      private def self.emit_nir_block(io : IO, node : IR::NIR::Block, plans : Planning::Plans::Table, depth : Int32) : Nil
        indent(io, depth)
        io << "(block"
        attr(io, "id", node.id.to_s)
        io << '\n'
        node.body.each { |stmt| emit_nir_stmt(io, stmt, plans, depth + 1) }
        indent(io, depth)
        io << ")\n"
      end

      private def self.emit_lir_func(io : IO, function : IR::LIR::Func) : Nil
        io << "(func"
        attr(io, "name", function.name)
        attr(io, "return", type_name(function.return_type))
        io << '\n'
        function.params.each { |param| emit_lir_param(io, param, 1) }
        function.body.each { |stmt| emit_lir_stmt(io, stmt, 1) }
        io << ")\n"
      end

      private def self.emit_lir_stmt(io : IO, stmt : IR::LIR::Stmt, depth : Int32) : Nil
        indent(io, depth)
        case stmt
        when IR::LIR::ExternalCall
          io << "(external-call"
          attr(io, "target", external_target(stmt.target))
          emit_lir_values(io, stmt.args, depth)
        when IR::LIR::Assign
          io << "(assign"
          attr(io, "target", stmt.target)
          attr(io, "mode", stmt.mode.to_s)
          emit_lir_value_child(io, stmt.value, depth)
        when IR::LIR::Discard
          io << "(discard"
          emit_lir_value_child(io, stmt.value, depth)
        when IR::LIR::AbruptExit
          io << "(abrupt"
          attr(io, "shape", stmt.shape.to_s)
          if value = stmt.value
            emit_lir_value_child(io, value, depth)
          else
            finish_empty(io)
          end
        when IR::LIR::If
          io << "(if\n"
          emit_lir_value(io, stmt.cond, depth + 1)
          stmt.then_body.each { |child| emit_lir_stmt(io, child, depth + 1) }
          stmt.else_body.each { |child| emit_lir_stmt(io, child, depth + 1) }
          indent(io, depth)
          io << ")\n"
        when IR::LIR::While
          io << "(while\n"
          emit_lir_value(io, stmt.cond, depth + 1)
          stmt.body.each { |child| emit_lir_stmt(io, child, depth + 1) }
          indent(io, depth)
          io << ")\n"
        else
          io << '(' << stmt.class.name.split("::").last.underscore
          emit_lir_children(io, IR::LIR::Walk.children(stmt), depth)
        end
      end

      private def self.emit_lir_param(io : IO, param : IR::LIR::Param, depth : Int32) : Nil
        indent(io, depth)
        io << "(param"
        attr(io, "name", param.name)
        attr(io, "type", type_name(param.type))
        param.proc_signature.try { |signature| attr(io, "signature", proc_signature(signature)) }
        attr(io, "repr", param.repr.to_s) unless param.repr.native?
        io << ")\n"
      end

      private def self.emit_lir_value_child(io : IO, value : IR::LIR::Value, depth : Int32) : Nil
        io << '\n'
        emit_lir_value(io, value, depth + 1)
        indent(io, depth)
        io << ")\n"
      end

      private def self.emit_lir_values(io : IO, values : Array(IR::LIR::Value), depth : Int32) : Nil
        if values.empty?
          finish_empty(io)
        else
          io << '\n'
          values.each { |value| emit_lir_value(io, value, depth + 1) }
          indent(io, depth)
          io << ")\n"
        end
      end

      private def self.emit_lir_value(io : IO, value : IR::LIR::Value, depth : Int32) : Nil
        indent(io, depth)
        case value
        when IR::LIR::IntConst
          io << "(int"
          attr(io, "type", type_name(value.type))
          attr(io, "value", value.value)
          io << ")\n"
        when IR::LIR::StringConst
          io << "(string"
          attr(io, "value", value.value)
          io << ")\n"
        when IR::LIR::BoolConst
          io << "(bool"
          attr(io, "value", value.value.to_s)
          io << ")\n"
        when IR::LIR::Temp
          io << "(temp"
          attr(io, "name", value.name)
          io << ")\n"
        when IR::LIR::Call
          io << "(call"
          attr(io, "name", value.name)
          emit_lir_values(io, value.args, depth)
        when IR::LIR::ExternalCallValue
          io << "(external-call-value"
          attr(io, "target", external_target(value.target))
          emit_lir_values(io, value.args, depth)
        when IR::LIR::Binary
          io << "(binary"
          attr(io, "operator", value.operator)
          emit_lir_binary_values(io, value.left, value.right, depth)
        when IR::LIR::IntegerOperationValue
          io << "(integer-operation"
          attr(io, "operation", value.kind.to_s)
          attr(io, "type", type_name(value.type))
          emit_lir_binary_values(io, value.left, value.right, depth)
        when IR::LIR::IntegerBitNot
          io << "(integer-bit-not"
          attr(io, "type", type_name(value.type))
          io << '\n'
          emit_lir_value(io, value.operand, depth + 1)
          indent(io, depth)
          io << ")\n"
        when IR::LIR::IntegerConvert
          io << "(integer-convert"
          attr(io, "mode", value.mode.to_s)
          attr(io, "source", type_name(value.source))
          attr(io, "target", type_name(value.target))
          io << '\n'
          emit_lir_value(io, value.value, depth + 1)
          indent(io, depth)
          io << ")\n"
        when IR::LIR::CheckedArithmetic
          io << "(checked-arithmetic"
          attr(io, "operation", value.operation.to_s)
          attr(io, "type", type_name(value.type))
          attr(io, "strategy", value.strategy.to_s)
          emit_lir_binary_values(io, value.left, value.right, depth)
        when IR::LIR::IfValue
          io << "(if-value"
          attr(io, "type", type_name(value.type))
          io << '\n'
          emit_lir_value(io, value.cond, depth + 1)
          emit_lir_value(io, value.then_value, depth + 1)
          emit_lir_value(io, value.else_value, depth + 1)
          indent(io, depth)
          io << ")\n"
        when IR::LIR::RescueValue
          io << "(rescue-value"
          attr(io, "type", type_name(value.type))
          io << '\n'
          emit_lir_rescue_arm(io, "body", value.body, depth + 1)
          value.clauses.each do |clause|
            indent(io, depth + 1)
            io << "(clause"
            attr(io, "types", clause.types.empty? ? "Exception" : clause.types.join(" | "))
            attr(io, "binding", clause.binding)
            io << '\n'
            emit_lir_rescue_arm(io, "arm", clause.body, depth + 2)
            indent(io, depth + 1)
            io << ")\n"
          end
          value.else_arm.try { |arm| emit_lir_rescue_arm(io, "else", arm, depth + 1) }
          value.ensure_body.try do |body|
            indent(io, depth + 1)
            io << "(ensure\n"
            body.each { |stmt| emit_lir_stmt(io, stmt, depth + 2) }
            indent(io, depth + 1)
            io << ")\n"
          end
          indent(io, depth)
          io << ")\n"
        else
          io << '(' << value.class.name.split("::").last.underscore
          emit_lir_children(io, IR::LIR::Walk.children(value), depth)
        end
      end

      private def self.emit_lir_children(io : IO, children : Array(IR::LIR::Walk::Node), depth : Int32) : Nil
        if children.empty?
          finish_empty(io)
          return
        end

        io << '\n'
        children.each do |child|
          case child
          when IR::LIR::Stmt  then emit_lir_stmt(io, child, depth + 1)
          when IR::LIR::Value then emit_lir_value(io, child, depth + 1)
          end
        end
        indent(io, depth)
        io << ")\n"
      end

      private def self.emit_lir_rescue_arm(io : IO, name : String, arm : IR::LIR::RescueValue::Arm, depth : Int32) : Nil
        indent(io, depth)
        io << '(' << name << '\n'
        arm.body.each { |stmt| emit_lir_stmt(io, stmt, depth + 1) }
        arm.value.try { |value| emit_lir_value(io, value, depth + 1) }
        indent(io, depth)
        io << ")\n"
      end

      private def self.emit_lir_checked(io : IO, name : String, left : IR::LIR::Value, right : IR::LIR::Value, depth : Int32, type : IR::Type) : Nil
        io << '(' << name
        attr(io, "type", type_name(type))
        io << '\n'
        emit_lir_value(io, left, depth + 1)
        emit_lir_value(io, right, depth + 1)
        indent(io, depth)
        io << ")\n"
      end

      private def self.emit_lir_binary_values(io : IO, left : IR::LIR::Value, right : IR::LIR::Value, depth : Int32) : Nil
        io << '\n'
        emit_lir_value(io, left, depth + 1)
        emit_lir_value(io, right, depth + 1)
        indent(io, depth)
        io << ")\n"
      end

      private def self.attr(io : IO, name : String, value : String?) : Nil
        return unless value
        io << ' ' << name << '=' << value.inspect
      end

      private def self.finish_empty(io : IO) : Nil
        io << ")\n"
      end

      private def self.indent(io : IO, depth : Int32) : Nil
        io << "  " * depth
      end

      private def self.type_name(type : IR::Type?) : String?
        type.try(&.to_s)
      end

      private def self.assign_target_name(target : IR::NIR::Expr) : String
        case target
        when IR::NIR::InstanceVar then "@#{target.name}"
        when IR::NIR::Local       then target.name
        else                           target.class.name.split("::").last
        end
      end

      private def self.proc_signature(signature : IR::ProcSignature) : String
        "(#{signature.param_types.join(", ")}) -> #{signature.return_type || "Nil"}"
      end

      private def self.external_target(target : IR::LIR::ExternalTarget) : String
        prefix = target.package_name ? "#{target.package_name}." : ""
        target.receiver_method? ? ".#{target.name}" : "#{prefix}#{target.name}"
      end
    end
  end
end
