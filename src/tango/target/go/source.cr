module Tango
  module Target
    module Go
      module Source
        class ImportConflict < Exception
          getter path : String
          getter identifiers : Array(String?)

          def initialize(@path : String, @identifiers : Array(String?))
            super("Go import #{path.inspect} requested with incompatible identifiers: #{identifiers.map(&.inspect).join(", ")}")
          end
        end

        def self.emit(file : IR::File) : String
          requirements = Runtime::Requirement.closure(file.requirements)

          String.build do |io|
            io << "package " << file.package_name << "\n\n"

            imports = runtime_imports(requirements)
            helpers = runtime_helpers(requirements)

            emit_imports(io, imports)
            emit_helpers(io, helpers)
            emit_enums(io, file.enum_decls)
            emit_structs(io, file.struct_decls)
            emit_globals(io, file.global_decls)

            file.method_decls.each do |method|
              emit_func(io, method)
              io << "\n"
            end

            file.functions.each_with_index do |function, index|
              io << "\n" if index > 0
              emit_func(io, function)
            end
          end
        end

        private def self.runtime_imports(requirements : Array(Runtime::Requirement)) : Array(Runtime::Import)
          imports = requirements.compact_map(&.as?(Runtime::Import))
          imports.group_by(&.path).each do |path, entries|
            default_identifier = path.split('/').last
            identifiers = entries.map do |entry|
              entry.identifier == default_identifier ? nil : entry.identifier
            end.uniq
            raise ImportConflict.new(path, identifiers) if identifiers.size > 1
          end
          imports.uniq(&.path)
        end

        private def self.runtime_helpers(requirements : Array(Runtime::Requirement)) : Array(Runtime::Helper)
          requirements.compact_map(&.as?(Runtime::Helper))
        end

        private def self.emit_imports(io : IO, imports : Array(Runtime::Import))
          imports.each do |import|
            io << "import "
            import.identifier.try do |identifier|
              io << identifier << ' ' unless identifier == import.path.split('/').last
            end
            io << import.path.inspect << "\n"
          end

          io << "\n" unless imports.empty?
        end

        private def self.emit_helpers(io : IO, helpers : Array(Runtime::Helper))
          helpers.each do |helper|
            io << helper.snippet.code
            io << "\n" unless helper.snippet.code.ends_with?('\n')
            io << "\n"
          end
        end

        private def self.emit_structs(io : IO, structs : Array(IR::StructDecl))
          structs.each do |decl|
            io << "type " << decl.name << " struct {\n"
            decl.fields.each { |field| io << "\t" << field.name << " " << field.type_name << "\n" }
            io << "}\n\n"
          end
        end

        private def self.emit_enums(io : IO, enums : Array(IR::EnumDecl))
          enums.each do |decl|
            io << "type " << decl.name << ' ' << decl.base_type << "\n\n"
            io << "const (\n"
            decl.members.each do |member|
              io << "\t" << member.name << ' ' << decl.name << " = " << member.value << "\n"
            end
            io << ")\n\n"
          end
        end

        private def self.emit_globals(io : IO, globals : Array(IR::GlobalDecl))
          globals.each do |decl|
            decl.line.try { |line| emit_line_directive(io, line) }
            io << "var " << decl.name << ' ' << decl.type_name << " = "
            emit_expr(io, decl.value)
            io << "\n\n"
          end
        end

        private def self.emit_func(io : IO, function : IR::Func)
          function.line.try { |line| emit_line_directive(io, line) }
          io << "func "
          function.receiver.try { |receiver| io << '(' << receiver.name << ' ' << receiver.type_name << ") " }
          io << function.name << "("
          function.params.each_with_index do |param, index|
            io << ", " if index > 0
            io << param.name << " " << param.type_name
          end
          io << ")"
          function.return_type.try { |return_type| io << " " << return_type }
          io << " {\n"
          function.body.each do |stmt|
            emit_stmt(io, stmt, 1)
          end
          io << "}\n"
        end

        private def self.emit_stmt(io : IO, stmt : IR::Stmt, depth : Int32)
          case stmt
          when IR::LineDirective
            emit_line_directive(io, stmt)
          when IR::ExprStmt
            indent(io, depth)
            emit_expr(io, stmt.expr)
            io << "\n"
          when IR::AssignStmt
            indent(io, depth)
            emit_expr(io, stmt.target)
            io << (stmt.mode.declare? ? " := " : " = ")
            emit_expr(io, stmt.value)
            io << "\n"
          when IR::MultiAssignStmt
            indent(io, depth)
            stmt.targets.each_with_index do |target, index|
              io << ", " if index > 0
              emit_expr(io, target)
            end
            io << (stmt.mode.declare? ? " := " : " = ")
            stmt.values.each_with_index do |value, index|
              io << ", " if index > 0
              emit_expr(io, value)
            end
            io << "\n"
          when IR::VarDecl
            indent(io, depth)
            io << "var " << stmt.target << " " << stmt.type_name << "\n"
          when IR::ReturnStmt
            indent(io, depth)
            io << "return"
            stmt.value.try do |value|
              io << " "
              emit_expr(io, value)
            end
            io << "\n"
          when IR::IfStmt
            indent(io, depth)
            io << "if "
            emit_expr(io, stmt.cond)
            io << " {\n"
            stmt.then_body.each { |child| emit_stmt(io, child, depth + 1) }
            indent(io, depth)
            io << "}"
            unless stmt.else_body.empty?
              io << " else {\n"
              stmt.else_body.each { |child| emit_stmt(io, child, depth + 1) }
              indent(io, depth)
              io << "}"
            end
            io << "\n"
          when IR::DeferStmt
            indent(io, depth)
            io << "defer "
            emit_expr(io, stmt.call)
            io << "\n"
          when IR::BranchStmt
            indent(io, depth)
            io << (stmt.kind.break? ? "break" : "continue") << "\n"
          when IR::ForStmt
            indent(io, depth)
            io << "for"
            stmt.cond.try do |cond|
              io << ' '
              emit_expr(io, cond)
            end
            io << " {\n"
            stmt.body.each { |child| emit_stmt(io, child, depth + 1) }
            indent(io, depth)
            io << "}\n"
          when IR::RangeStmt
            indent(io, depth)
            io << "for _, " << stmt.value_ident << " := range "
            emit_expr(io, stmt.source)
            io << " {\n"
            stmt.body.each { |child| emit_stmt(io, child, depth + 1) }
            indent(io, depth)
            io << "}\n"
          when IR::SendStmt
            indent(io, depth)
            emit_expr(io, stmt.channel)
            io << " <- "
            emit_expr(io, stmt.value)
            io << "\n"
          when IR::GoStmt
            indent(io, depth)
            io << "go "
            emit_expr(io, stmt.call)
            io << "\n"
          when IR::SelectStmt
            indent(io, depth)
            io << "select {\n"
            stmt.clauses.each do |clause|
              indent(io, depth)
              io << "case "
              if send_value = clause.send_value
                emit_expr(io, clause.channel)
                io << " <- "
                emit_expr(io, send_value)
              elsif clause.value_ident.empty?
                io << "<-"
                emit_expr(io, clause.channel)
              elsif clause.ok_ident.empty?
                io << clause.value_ident << " := <-"
                emit_expr(io, clause.channel)
              else
                io << clause.value_ident << ", " << clause.ok_ident << " := <-"
                emit_expr(io, clause.channel)
              end
              io << ":\n"
              clause.body.each { |child| emit_stmt(io, child, depth + 1) }
            end
            stmt.default.try do |default|
              indent(io, depth)
              io << "default:\n"
              default.each { |child| emit_stmt(io, child, depth + 1) }
            end
            indent(io, depth)
            io << "}\n"
          when IR::Switch
            indent(io, depth)
            io << "switch "
            emit_expr(io, stmt.value)
            io << " {\n"
            stmt.cases.each do |clause|
              indent(io, depth)
              if label = clause.label
                io << "case "
                emit_expr(io, label)
                io << ":\n"
              else
                io << "default:\n"
              end
              clause.body.each { |child| emit_stmt(io, child, depth + 1) }
            end
            indent(io, depth)
            io << "}\n"
          end
        end

        private def self.emit_line_directive(io : IO, line : IR::LineDirective) : Nil
          io << "//line " << line.file << ":" << line.line << ":" << line.column << "\n"
        end

        private def self.indent(io : IO, depth : Int32)
          depth.times { io << "\t" }
        end

        private def self.emit_expr(io : IO, expr : IR::Expr)
          case expr
          when IR::Ident
            io << expr.name
          when IR::IntLit
            io << expr.value
          when IR::FloatLit
            io << expr.value
          when IR::StringLit
            io << expr.value.inspect
          when IR::BoolLit
            io << expr.value
          when IR::Selector
            emit_expr(io, expr.receiver)
            io << "." << expr.name
          when IR::Call
            emit_expr(io, expr.callee)
            io << "("
            expr.args.each_with_index do |arg, index|
              io << ", " if index > 0
              emit_expr(io, arg)
            end
            io << ")"
          when IR::GenericInst
            emit_expr(io, expr.callee)
            io << "[" << expr.type_args.join(", ") << "]"
          when IR::Deref
            io << "(*"
            emit_expr(io, expr.expr)
            io << ")"
          when IR::Index
            emit_expr(io, expr.receiver)
            io << "["
            emit_expr(io, expr.index)
            io << "]"
          when IR::TypeAssert
            emit_expr(io, expr.value)
            io << ".(" << expr.type_name << ")"
          when IR::Binary
            emit_expr(io, expr.left)
            io << " " << expr.operator << " "
            emit_expr(io, expr.right)
          when IR::Not
            io << "!"
            if expr.expr.is_a?(IR::Binary)
              io << "("
              emit_expr(io, expr.expr)
              io << ")"
            else
              emit_expr(io, expr.expr)
            end
          when IR::BitNot
            io << "^"
            emit_expr(io, expr.expr)
          when IR::CompositeLit
            io << expr.type_name << "{"
            expr.fields.each_with_index do |field, index|
              io << ", " if index > 0
              io << field[0] << ": "
              emit_expr(io, field[1])
            end
            io << "}"
          when IR::AddrOf
            io << "&"
            emit_expr(io, expr.expr)
          when IR::RecvExpr
            io << "<-"
            emit_expr(io, expr.channel)
          when IR::MakeChan
            io << "make(chan " << expr.element_type
            expr.capacity.try do |capacity|
              io << ", "
              emit_expr(io, capacity)
            end
            io << ")"
          when IR::FuncLit
            emit_func_lit(io, expr)
          end
        end

        private def self.emit_func_lit(io : IO, expr : IR::FuncLit)
          io << "func("
          expr.params.each_with_index do |param, index|
            io << ", " if index > 0
            io << param.name << " " << param.type_name
          end
          io << ")"
          expr.return_type.try { |return_type| io << " " << return_type }
          io << " {\n"
          expr.body.each { |stmt| emit_stmt(io, stmt, 1) }
          io << "}"
        end
      end
    end
  end
end
