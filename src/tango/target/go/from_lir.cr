module Tango
  module Target
    module Go
      class FromLIR
        @names = EmissionNames.new
        @function = FunctionContext.new

        private def initialize(@types : TypeSpeller)
        end

        def self.translate(program : Tango::IR::LIR::Program) : IR::File
          requirements = [] of Runtime::Requirement
          new(TypeSpeller.new(program, requirements)).translate(program, requirements)
        end

        def translate(program : Tango::IR::LIR::Program, requirements : Array(Runtime::Requirement)) : IR::File
          struct_decls = program.types.map { |type| translate_struct(type) }
          struct_decls.concat(program.unions.map { |union| carrier_struct(union) })
          method_decls = program.unions.map { |union| carrier_string_method(union, requirements) }
          functions = program.types.flat_map { |type| exception_runtime_functions(type) }
          functions.concat(program.conversions.map { |conversion| carrier_conversion_func(conversion) })
          functions.concat(program.functions.map { |function| translate_func(function, requirements) })

          body = [] of IR::Stmt
          program.body.each do |stmt|
            body.concat(translate_stmt(stmt, requirements))
          end
          body = translate_entrypoint(program.uncaught_exception, body, requirements)
          functions << IR::Func.new("main", body)

          enum_decls = program.enums.map { |definition| translate_enum(definition) }
          IR::File.new("main", requirements, functions, struct_decls, method_decls, enum_decls)
        end

        private def translate_enum(definition : Tango::IR::LIR::EnumType) : IR::EnumDecl
          members = definition.members.map { |member| IR::EnumDecl::Member.new(member.target_name, member.value) }
          IR::EnumDecl.new(definition.target_name, go_type(definition.base_type), members)
        end

        # The entrypoint carries a lowering-committed policy. The target spells
        # it as typed defer syntax and asks the runtime registry only for the
        # helper implementation; it does not inspect source raises or facts.
        private def translate_entrypoint(strategy : Tango::IR::UncaughtExceptionStrategy, body : Array(IR::Stmt), requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          case strategy
          in .crystal_style?
            requirements << Runtime::Helper.new("tangoUncaughtException")
            defer = IR::DeferStmt.new(IR::Call.new(IR::Ident.new("tangoUncaughtException"), [] of IR::Expr))
            [defer.as(IR::Stmt)] + body
          end
        end

        private def translate_struct(type : Tango::IR::LIR::StructType) : IR::StructDecl
          fields = type.fields.map { |field| IR::StructDecl::Field.new(field.name, go_type(field.type)) }
          fields << IR::StructDecl::Field.new("_pad", "byte") if type.identity_padding?
          IR::StructDecl.new(type.name, fields)
        end

        private def translate_func(function : Tango::IR::LIR::Func, requirements : Array(Runtime::Requirement)) : IR::Func
          if function.params.any? { |param| param.repr.exception_interface? }
            requirements << Runtime::Helper.new("tangoException")
          end
          params = function.params.map { |param| IR::Param.new(param.name, go_param_type(param)) }
          body = @function.within(function.return_type) do
            translate_body(function.body, requirements)
          end

          IR::Func.new(function.name, body, params, func_return_type(function.return_type), line_directive(function.loc))
        end

        private def func_return_type(return_type : Tango::IR::Type?) : String?
          return nil if return_type.nil? || return_type.nil_type?

          go_type(return_type)
        end

        private def translate_stmt(stmt : Tango::IR::LIR::Stmt, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          translated = case stmt
                       when Tango::IR::LIR::ExternalCall
                         [IR::ExprStmt.new(external_call(stmt.target, stmt.args, requirements))] of IR::Stmt
                       when Tango::IR::LIR::Assign
                         if value = stmt.value.as?(Tango::IR::LIR::IfValue)
                           translate_if_value_assign(stmt.target, stmt.mode, value, requirements)
                         elsif value = stmt.value.as?(Tango::IR::LIR::RescueValue)
                           translate_rescue_value_assign(stmt.target, stmt.mode, value, requirements)
                         else
                           [IR::AssignStmt.new(IR::Ident.new(stmt.target), assign_mode(stmt.mode), translate_value(stmt.value, requirements))] of IR::Stmt
                         end
                       when Tango::IR::LIR::FieldAssign
                         [IR::AssignStmt.new(IR::Selector.new(translate_value(stmt.receiver, requirements), stmt.field), IR::AssignStmt::Mode::Reassign, translate_value(stmt.value, requirements))] of IR::Stmt
                       when Tango::IR::LIR::Discard
                         translate_discard(stmt.value, requirements)
                       when Tango::IR::LIR::If
                         [IR::IfStmt.new(
                           translate_value(stmt.cond, requirements),
                           translate_body(stmt.then_body, requirements),
                           translate_body(stmt.else_body, requirements)
                         )] of IR::Stmt
                       when Tango::IR::LIR::While
                         [translate_while(stmt, requirements)] of IR::Stmt
                       when Tango::IR::LIR::Handler
                         translate_handler(stmt, requirements)
                       when Tango::IR::LIR::AbruptExit
                         translate_abrupt_exit(stmt, requirements)
                       when Tango::IR::LIR::ChanSend
                         [IR::SendStmt.new(translate_value(stmt.channel, requirements), translate_value(stmt.value, requirements))] of IR::Stmt
                       when Tango::IR::LIR::ChanClose
                         [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("close"), [translate_value(stmt.channel, requirements)] of IR::Expr))] of IR::Stmt
                       when Tango::IR::LIR::Spawn
                         [IR::GoStmt.new(IR::Call.new(translate_value(stmt.proc, requirements), [] of IR::Expr))] of IR::Stmt
                       when Tango::IR::LIR::StringEachChar
                         [translate_string_each_char(stmt, requirements)] of IR::Stmt
                       when Tango::IR::LIR::Select
                         [translate_select(stmt, requirements)] of IR::Stmt
                       when Tango::IR::LIR::UnsupportedStmt
                         raise "unsupported LIR statement: #{stmt.reason}"
                         [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [IR::StringLit.new(stmt.reason)] of IR::Expr))] of IR::Stmt
                       else
                         raise "unsupported LIR statement: #{stmt.class.name}"
                         [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [IR::StringLit.new("unsupported LIR statement")] of IR::Expr))] of IR::Stmt
                       end
          prepend_line_directive(stmt.loc, translated)
        end

        private def translate_discard(value : Tango::IR::LIR::Value, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          if value.is_a?(Tango::IR::LIR::IfValue)
            return [IR::IfStmt.new(
              translate_value(value.cond, requirements),
              translate_discard(value.then_value, requirements),
              translate_discard(value.else_value, requirements)
            )] of IR::Stmt
          end

          # A bare call statement is valid Go and is the only valid spelling
          # for a void call (`_ = f()` is an error when f returns nothing).
          # Any other discarded value needs `_ =` to be a legal statement.
          if value.is_a?(Tango::IR::LIR::Call) || value.is_a?(Tango::IR::LIR::ExternalCallValue) || value.is_a?(Tango::IR::LIR::InvokeClosure)
            [IR::ExprStmt.new(translate_value(value, requirements))] of IR::Stmt
          else
            [IR::AssignStmt.new(IR::Ident.new("_"), IR::AssignStmt::Mode::Reassign, translate_value(value, requirements))] of IR::Stmt
          end
        end

        # Each arm's kind already commits its receive policy. Checked receive
        # guards comma-ok with ClosedError; pointer receive? binds the raw value;
        # carrier receive? initializes the nil zero value and boxes only on ok.
        private def translate_select(stmt : Tango::IR::LIR::Select, requirements : Array(Runtime::Requirement)) : IR::SelectStmt
          clauses = stmt.arms.map do |arm|
            channel = translate_value(arm.channel, requirements)
            case arm.kind
            in .receive?
              ok = fresh_ok
              guard = IR::IfStmt.new(
                IR::Not.new(IR::Ident.new(ok)),
                [typed_channel_closed_panic(requirements).as(IR::Stmt)],
                [] of IR::Stmt
              )
              body = [guard.as(IR::Stmt)]
              body.concat(translate_body(arm.body, requirements))
              IR::SelectStmt::Clause.new(channel, nil, arm.binding || "_", ok, body)
            in .receive_maybe_pointer?
              binding = arm.binding
              IR::SelectStmt::Clause.new(channel, nil, binding || "", "", translate_body(arm.body, requirements))
            in .receive_maybe_carrier?
              binding = arm.binding
              unless binding
                next IR::SelectStmt::Clause.new(channel, nil, "", "", translate_body(arm.body, requirements))
              end
              union = arm.result_type || raise "carrier select receive? without a result type"
              received = @names.temp("received")
              ok = fresh_ok
              box = translate_carrier_box(union, arm.element, IR::Ident.new(received))
              body = [
                IR::VarDecl.new(binding, go_type(union)).as(IR::Stmt),
                IR::IfStmt.new(
                  IR::Ident.new(ok),
                  [IR::AssignStmt.new(IR::Ident.new(binding), IR::AssignStmt::Mode::Reassign, box).as(IR::Stmt)],
                  [] of IR::Stmt
                ).as(IR::Stmt),
              ]
              body.concat(translate_body(arm.body, requirements))
              IR::SelectStmt::Clause.new(channel, nil, received, ok, body)
            in .send?
              send_value = arm.value.try { |value| translate_value(value, requirements) }
              IR::SelectStmt::Clause.new(channel, send_value, "", "", translate_body(arm.body, requirements))
            end
          end
          default = stmt.default.try { |stmts| translate_body(stmts, requirements) }
          IR::SelectStmt.new(clauses, default)
        end

        private def typed_channel_closed_panic(requirements : Array(Runtime::Requirement)) : IR::ExprStmt
          requirements << Runtime::Helper.new("tangoChannelClosedError")
          error = IR::AddrOf.new(IR::CompositeLit.new("tangoChannelClosedError", [
            {"message", IR::StringLit.new("Channel is closed").as(IR::Expr)},
          ] of Tuple(String, IR::Expr)))
          IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [error.as(IR::Expr)]))
        end

        private def translate_while(stmt : Tango::IR::LIR::While, requirements : Array(Runtime::Requirement)) : IR::ForStmt
          target = stmt.target
          context = @function.current_handler
          context.inner_loops << target if context && target
          body = translate_body(stmt.body, requirements)
          cond = stmt.cond.as?(Tango::IR::LIR::BoolConst).try(&.value) == true ? nil : translate_value(stmt.cond, requirements)
          IR::ForStmt.new(cond, body)
        end

        private def fresh_ok : String
          @names.ok
        end

        private def prepend_line_directive(loc : Tango::IR::LIR::SourceLoc?, stmts : Array(IR::Stmt)) : Array(IR::Stmt)
          line = line_directive(loc)
          return stmts unless line

          [line.as(IR::Stmt)] + stmts
        end

        private def line_directive(loc : Tango::IR::LIR::SourceLoc?) : IR::LineDirective?
          loc.try { |source| IR::LineDirective.new(source.file, source.line, source.column) }
        end

        private def translate_body(stmts : Array(Tango::IR::LIR::Stmt), requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          body = [] of IR::Stmt
          stmts.each { |stmt| body.concat(translate_stmt(stmt, requirements)) }
          body
        end

        # A handler is an immediately invoked closure. The ensure defer is
        # registered first (therefore runs last); the recover defer is second.
        # Any return/break/next translated while the handler context is live is
        # encoded into an outer signal and replayed after the call through the
        # same translate_abrupt_exit chokepoint.
        private def translate_handler(stmt : Tango::IR::LIR::Handler, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          context = HandlerContext.new(@names.temp("handler"))
          ensure_body, clause_bodies, protected_body, else_body = @function.with_handler(context) do
            {
              stmt.ensure_body.try { |body| translate_body(body, requirements) },
              stmt.clauses.map { |clause| {clause, translate_body(clause.body, requirements)} },
              translate_body(stmt.body, requirements),
              stmt.else_body.try { |body| translate_body(body, requirements) },
            }
          end

          result = assemble_handler(context, ensure_body, clause_bodies, protected_body, else_body, requirements)
          if stmt.no_return?
            result << IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [IR::StringLit.new("unreachable exception handler fallthrough").as(IR::Expr)]))
          end
          result
        end

        private def translate_recover(clause_bodies : Array(Tuple(C, Array(IR::Stmt))), done : String?, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt) forall C
          requirements << Runtime::Helper.new("tangoException")
          recovered = @names.temp("panic")
          needs_exception = clause_bodies.any? do |(clause, _body)|
            !clause.binding.nil? || !clause.catch_all?
          end
          exception = needs_exception ? @names.temp("exception") : "_"
          ok = @names.temp("exception_ok")
          repanic = [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [IR::Ident.new(recovered).as(IR::Expr)])).as(IR::Stmt)]

          body = [] of IR::Stmt
          body << IR::AssignStmt.new(IR::Ident.new(recovered), IR::AssignStmt::Mode::Declare, IR::Call.new(IR::Ident.new("recover"), [] of IR::Expr))
          body << IR::IfStmt.new(
            IR::Binary.new(IR::Ident.new(recovered), "==", IR::Ident.new("nil")),
            [IR::ReturnStmt.new(nil).as(IR::Stmt)],
            [] of IR::Stmt
          )
          if done
            body << IR::IfStmt.new(IR::Ident.new(done), repanic, [] of IR::Stmt)
          end
          body << IR::MultiAssignStmt.new(
            [IR::Ident.new(exception).as(IR::Expr), IR::Ident.new(ok).as(IR::Expr)],
            IR::AssignStmt::Mode::Declare,
            [IR::TypeAssert.new(IR::Ident.new(recovered), "tangoException").as(IR::Expr)]
          )
          body << IR::IfStmt.new(IR::Not.new(IR::Ident.new(ok)), repanic, [] of IR::Stmt)
          body.concat(rescue_dispatch(clause_bodies, exception, recovered))
          body
        end

        private def rescue_dispatch(clause_bodies : Array(Tuple(C, Array(IR::Stmt))), exception : String, recovered : String) : Array(IR::Stmt) forall C
          fallback = [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [IR::Ident.new(recovered).as(IR::Expr)])).as(IR::Stmt)]

          clause_bodies.reverse_each do |clause, translated|
            arm = [] of IR::Stmt
            clause.binding.try do |binding|
              arm << IR::AssignStmt.new(IR::Ident.new(binding), IR::AssignStmt::Mode::Declare, IR::Ident.new(exception))
            end
            arm.concat(translated)
            arm << IR::ReturnStmt.new(nil) unless arm.last?.is_a?(IR::ReturnStmt)

            if clause.catch_all?
              fallback = arm
            else
              condition = rescue_condition(clause.types, exception)
              fallback = [IR::IfStmt.new(condition, arm, fallback).as(IR::Stmt)]
            end
          end
          fallback
        end

        private def rescue_condition(types : Array(Tango::IR::Type), exception : String) : IR::Expr
          conditions = types.map do |type|
            IR::Call.new(
              IR::Selector.new(IR::Ident.new(exception), "tangoIsA"),
              [IR::StringLit.new(type.name || type.to_s).as(IR::Expr)]
            ).as(IR::Expr)
          end
          conditions.reduce do |left, right|
            IR::Binary.new(left, "||", right).as(IR::Expr)
          end
        end

        # Go has no if-expression, so a Return whose value is an IfValue
        # destructures into an if statement that returns from each branch —
        # the same shape as translate_if_value_assign, and recursive so a
        # nested if-in-tail (elsif chains) lowers correctly.
        private def translate_abrupt_exit(stmt : Tango::IR::LIR::AbruptExit, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          case stmt.shape
          in .return?
            if value = stmt.value.as?(Tango::IR::LIR::RescueValue)
              translate_rescue_value_return(value, requirements)
            elsif intercept_exit?(stmt)
              intercept_exit(stmt, requirements)
            else
              translate_return(stmt.value, requirements)
            end
          in .break?
            intercept_exit?(stmt) ? intercept_exit(stmt, requirements) : [IR::BranchStmt.new(IR::BranchStmt::Kind::Break).as(IR::Stmt)]
          in .next?
            intercept_exit?(stmt) ? intercept_exit(stmt, requirements) : [IR::BranchStmt.new(IR::BranchStmt::Kind::Continue).as(IR::Stmt)]
          in .raise_message?
            requirements << Runtime::Helper.new("tangoExceptionValue")
            message = stmt.value || Tango::IR::LIR::StringConst.new("")
            exception = IR::AddrOf.new(IR::CompositeLit.new("tangoExceptionValue", [
              {"message", translate_value(message, requirements)},
            ] of Tuple(String, IR::Expr)))
            [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [exception.as(IR::Expr)])).as(IR::Stmt)]
          in .raise_exception?
            value = stmt.value || Tango::IR::LIR::UnsupportedValue.new("raise without an exception")
            [IR::ExprStmt.new(IR::Call.new(IR::Ident.new("panic"), [translate_value(value, requirements)])).as(IR::Stmt)]
          end
        end

        private def intercept_exit?(stmt : Tango::IR::LIR::AbruptExit) : Bool
          context = @function.current_handler
          return false unless context
          target = stmt.target
          return false if target && context.inner_loops.includes?(target)
          true
        end

        private def intercept_exit(stmt : Tango::IR::LIR::AbruptExit, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          context = @function.handler
          body = [] of IR::Stmt
          if value = stmt.value
            payload = context.payload ||= @names.temp("exit")
            body << IR::AssignStmt.new(IR::Ident.new(payload), IR::AssignStmt::Mode::Reassign, translate_value(value, requirements))
          end
          context.targets[stmt.shape] = stmt.target
          body << IR::AssignStmt.new(IR::Ident.new(context.signal), IR::AssignStmt::Mode::Reassign, IR::IntLit.new(context.tag_for(stmt.shape).to_s))
          body << IR::ReturnStmt.new(nil)
          body
        end

        private def translate_return(value : Tango::IR::LIR::Value?, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          if value.is_a?(Tango::IR::LIR::IfValue)
            [IR::IfStmt.new(
              translate_value(value.cond, requirements),
              translate_return(value.then_value, requirements),
              translate_return(value.else_value, requirements)
            )] of IR::Stmt
          else
            [IR::ReturnStmt.new(value.try { |inner| translate_value(inner, requirements) })] of IR::Stmt
          end
        end

        private def translate_if_value_assign(target : String, mode : Tango::IR::LIR::Assign::Mode, value : Tango::IR::LIR::IfValue, requirements : Array(Runtime::Requirement)) : Array(IR::Stmt)
          body = [] of IR::Stmt
          body << IR::VarDecl.new(target, go_type(value.type)) if mode.declare?
          body << IR::IfStmt.new(
            translate_value(value.cond, requirements),
            [IR::AssignStmt.new(IR::Ident.new(target), IR::AssignStmt::Mode::Reassign, translate_value(value.then_value, requirements))] of IR::Stmt,
            [IR::AssignStmt.new(IR::Ident.new(target), IR::AssignStmt::Mode::Reassign, translate_value(value.else_value, requirements))] of IR::Stmt
          )
          body
        end

        private def translate_if_value_expression(value : Tango::IR::LIR::IfValue, requirements : Array(Runtime::Requirement)) : IR::Expr
          body = [IR::IfStmt.new(
            translate_value(value.cond, requirements),
            translate_return(value.then_value, requirements),
            translate_return(value.else_value, requirements)
          ).as(IR::Stmt)]
          function = IR::FuncLit.new([] of IR::Param, go_type(value.type), body)
          IR::Call.new(function, [] of IR::Expr)
        end

        private def assign_mode(mode : Tango::IR::LIR::Assign::Mode) : IR::AssignStmt::Mode
          case mode
          in .declare?
            IR::AssignStmt::Mode::Declare
          in .reassign?
            IR::AssignStmt::Mode::Reassign
          end
        end

        # An external Go call in either binding form. The package form
        # (`@[Go("pkg.Func")]`) is `pkg.Func(args)`; the Go-method form
        # (`@[Go(".Method")]`) is `receiver.Method(rest)`, the receiver arriving
        # as the first arg (the frontend places it there).
        private def external_call(target : Tango::IR::LIR::ExternalTarget, args : Array(Tango::IR::LIR::Value), requirements : Array(Runtime::Requirement)) : IR::Call
          translated = args.map { |arg| translate_value(arg, requirements) }
          if target.receiver_method?
            IR::Call.new(IR::Selector.new(translated.first, target.name), translated[1..])
          else
            IR::Call.new(external_callee(target, requirements), translated)
          end
        end

        private def external_callee(target : Tango::IR::LIR::ExternalTarget, requirements : Array(Runtime::Requirement)) : IR::Expr
          return IR::Ident.new("panic") unless target.language == "go"

          if package_name = target.package_name
            requirements << Runtime::Import.new(package_name)
            IR::Selector.new(IR::Ident.new(package_name), target.name)
          else
            # A dotless @[Go] binding names a runtime helper snippet, not a
            # package function.
            requirements << Runtime::Helper.new(target.name)
            IR::Ident.new(target.name)
          end
        end

        private def go_param_type(param : Tango::IR::LIR::Param) : String
          return "tangoException" if param.repr.exception_interface?

          if signature = param.proc_signature
            go_proc_type(signature)
          else
            type = go_type(param.type)
            param.by_ref? ? "*#{type}" : type
          end
        end

        private def go_proc_type(signature : Tango::IR::LIR::ProcSignature) : String
          inputs = signature.param_types.map { |type| go_type(type) }.join(", ")
          return_type = signature.return_type
          if return_type.nil? || return_type.nil_type?
            "func(#{inputs})"
          else
            "func(#{inputs}) #{go_type(return_type)}"
          end
        end

        private def go_type(type : Tango::IR::Type?) : String
          @types.spell(type)
        end

        private def translate_scalar_stringify(value : Tango::IR::LIR::ScalarStringify, requirements : Array(Runtime::Requirement)) : IR::Expr
          case value.presentation
          when Tango::IR::ScalarPresentation::String
            translate_value(scalar_stringify_value(value), requirements)
          when Tango::IR::ScalarPresentation::Integer, Tango::IR::ScalarPresentation::Bool
            requirements << Runtime::Import.new("fmt")
            rendered = translate_value(scalar_stringify_value(value), requirements)
            IR::Call.new(IR::Selector.new(IR::Ident.new("fmt"), "Sprint"), [rendered] of IR::Expr)
          when Tango::IR::ScalarPresentation::Float
            requirements << Runtime::Helper.new("tangoFloatStr")
            rendered = translate_value(scalar_stringify_value(value), requirements)
            IR::Call.new(IR::Ident.new("tangoFloatStr"), [rendered] of IR::Expr)
          when Tango::IR::ScalarPresentation::Nil
            body = value.effects.flat_map { |effect| translate_stmt(effect, requirements) }
            body << IR::ReturnStmt.new(IR::StringLit.new(""))
            IR::Call.new(IR::FuncLit.new([] of IR::Param, "string", body), [] of IR::Expr)
          else
            raise "unhandled scalar presentation #{value.presentation}"
          end
        end

        private def scalar_stringify_value(value : Tango::IR::LIR::ScalarStringify) : Tango::IR::LIR::Value
          value.value || raise "#{value.presentation} scalar stringification has no value"
        end

        private def checked_arithmetic_helper(operation : Tango::IR::LIR::CheckedOperation, type : Tango::IR::Type, strategy : Tango::IR::CheckedArithmeticStrategy) : String
          width = type.width || raise "checked #{operation.to_s.downcase} has no integer width"
          compatible = case strategy
                       when .widening_round_trip? then width.bits < 64
                       when .signed_same_width?   then width.bits == 64 && width.signed?
                       when .unsigned_same_width? then width.bits == 64 && !width.signed?
                       end
          raise "checked arithmetic strategy #{strategy} does not match #{type}" unless compatible

          "tango#{operation}#{width}"
        end

        private def integer_conversion_helper(source : Tango::IR::Type, target : Tango::IR::Type) : String
          "tangoConvert#{integer_suffix(source)}To#{integer_suffix(target)}"
        end

        private def integer_suffix(type : Tango::IR::Type) : String
          width = type.width || raise "#{type} has no integer width"
          width.to_s
        end

        private def translate_integer_operation(value : Tango::IR::LIR::IntegerOperationValue, requirements : Array(Runtime::Requirement)) : IR::Expr
          left = translate_value(value.left, requirements)
          right = translate_value(value.right, requirements)
          operator = case value.kind
                     when .wrapping_add?, .wrapping_sub?, .wrapping_mul?
                       helper = "tango#{value.kind}#{integer_suffix(value.type)}"
                       requirements << Runtime::Helper.new(helper)
                       return IR::Call.new(IR::Ident.new(helper), [left, right] of IR::Expr)
                     when .pow?, .wrapping_pow?
                       prefix = value.kind.wrapping_pow? ? "tangoWrappingPow" : "tangoPow"
                       helper = "#{prefix}#{integer_suffix(value.type)}"
                       requirements << Runtime::Helper.new(helper)
                       return IR::Call.new(IR::Ident.new(helper), [left, right] of IR::Expr)
                     when .bit_and? then "&"
                     when .bit_or?  then "|"
                     when .bit_xor? then "^"
                     when .shift_left?, .shift_right?
                       helper = "tango#{value.kind}#{integer_suffix(value.type)}"
                       requirements << Runtime::Helper.new(helper)
                       return IR::Call.new(IR::Ident.new(helper), [left, right] of IR::Expr)
                     else
                       raise "unsupported integer operation #{value.kind}"
                     end
          IR::Binary.new(left, operator, right)
        end

        private def floor_arithmetic_helper(operation : Tango::IR::LIR::FloorOperation, type : Tango::IR::Type) : String
          "tangoFloor#{operation}#{@types.floor_arithmetic_suffix(type)}"
        end

        private def generic_helper(name : String, element : Tango::IR::Type) : IR::GenericInst
          IR::GenericInst.new(IR::Ident.new(name), [go_type(element)])
        end

        # The array operand for an index/len, dereferenced only when the array
        # representation is pointer-backed. The deref decision is asked of the
        # spelling chokepoint, never hardcoded here.
        private def array_operand(array : Tango::IR::LIR::Value, element : Tango::IR::Type, requirements : Array(Runtime::Requirement)) : IR::Expr
          operand = translate_value(array, requirements)
          @types.array_reference?(element) ? IR::Deref.new(operand) : operand
        end

        # A block/proc literal is a real function boundary. It must not write an
        # enclosing handler's signal from another invocation (or goroutine), and
        # its own return type governs any exits it contains.
        private def translate_closure(value : Tango::IR::LIR::Closure, requirements : Array(Runtime::Requirement)) : IR::FuncLit
          body = @function.within(value.return_type) do
            translate_body(value.body, requirements)
          end

          IR::FuncLit.new(
            value.params.map { |param| IR::Param.new(param.name, go_param_type(param)) },
            func_return_type(value.return_type),
            body
          )
        end

        private def translate_exception_value(value : Tango::IR::LIR::ExceptionValue, requirements : Array(Runtime::Requirement)) : IR::Expr
          helper = BUILTIN_EXCEPTION_HELPERS[value.class_name]? || raise "unsupported builtin exception #{value.class_name}"
          requirements << Runtime::Helper.new(helper)
          message = value.message.try { |inner| translate_value(inner, requirements) } || IR::StringLit.new("")
          IR::AddrOf.new(IR::CompositeLit.new(helper, [
            {"message", message},
          ] of Tuple(String, IR::Expr)))
        end

        # A fresh composite literal per box keeps inactive payloads zero, so
        # Go native `==` on carriers is correct. The nil variant's tag is read
        # from the committed LIR shape (`TypeSpeller#nil_tag`), never assumed.
        private def translate_box(box : Tango::IR::LIR::Box, requirements : Array(Runtime::Requirement)) : IR::Expr
          if member = box.member
            value = box.value || raise "carrier member #{member} has no payload"
            translate_carrier_box(box.union, member, translate_value(value, requirements))
          else
            translate_nil_carrier_box(box.union)
          end
        end

        private def translate_carrier_box(union : Tango::IR::Type, member : Tango::IR::Type, inner : IR::Expr) : IR::Expr
          carrier = @types.carrier(union)
          variant = @types.variant(union, member)
          fields = [
            {"tag", IR::IntLit.new(variant.tag.to_s).as(IR::Expr)},
            {"v#{variant.label}", inner},
          ] of Tuple(String, IR::Expr)
          IR::CompositeLit.new(carrier.name, fields)
        end

        private def translate_nil_carrier_box(union : Tango::IR::Type) : IR::Expr
          carrier = @types.carrier(union)
          fields = [{"tag", IR::IntLit.new(@types.nil_tag(union).to_s).as(IR::Expr)}] of Tuple(String, IR::Expr)
          IR::CompositeLit.new(carrier.name, fields)
        end

        private def translate_receive_maybe_box(value : Tango::IR::LIR::ChanReceiveMaybeBox, requirements : Array(Runtime::Requirement)) : IR::Expr
          received = @names.temp("received")
          ok = fresh_ok
          result = @names.temp("receive_result")
          box = translate_carrier_box(value.union, value.element, IR::Ident.new(received))
          body = [
            IR::MultiAssignStmt.new(
              [IR::Ident.new(received).as(IR::Expr), IR::Ident.new(ok).as(IR::Expr)],
              IR::AssignStmt::Mode::Declare,
              [IR::RecvExpr.new(translate_value(value.channel, requirements)).as(IR::Expr)]
            ).as(IR::Stmt),
            IR::VarDecl.new(result, go_type(value.union)).as(IR::Stmt),
            IR::IfStmt.new(
              IR::Ident.new(ok),
              [IR::AssignStmt.new(IR::Ident.new(result), IR::AssignStmt::Mode::Reassign, box).as(IR::Stmt)],
              [] of IR::Stmt
            ).as(IR::Stmt),
            IR::ReturnStmt.new(IR::Ident.new(result)).as(IR::Stmt),
          ]
          IR::Call.new(IR::FuncLit.new([] of IR::Param, go_type(value.union), body), [] of IR::Expr)
        end

        private def translate_receive_state(value : Tango::IR::LIR::ChanReceiveState, requirements : Array(Runtime::Requirement)) : IR::Expr
          received = @names.temp("received")
          ok = fresh_ok
          result = IR::CompositeLit.new(go_type(value.result_type), [
            {value.value_field, IR::Ident.new(received).as(IR::Expr)},
            {value.open_field, IR::Ident.new(ok).as(IR::Expr)},
          ] of Tuple(String, IR::Expr))
          body = [
            IR::MultiAssignStmt.new(
              [IR::Ident.new(received).as(IR::Expr), IR::Ident.new(ok).as(IR::Expr)],
              IR::AssignStmt::Mode::Declare,
              [IR::RecvExpr.new(translate_value(value.channel, requirements)).as(IR::Expr)]
            ).as(IR::Stmt),
            IR::ReturnStmt.new(result).as(IR::Stmt),
          ]
          IR::Call.new(IR::FuncLit.new([] of IR::Param, go_type(value.result_type), body), [] of IR::Expr)
        end

        # Carrier -> `.tag != <nil tag>`; pointer-nilable (no carrier decl) ->
        # `!= nil`.
        private def translate_nil_check(check : Tango::IR::LIR::NilCheck, requirements : Array(Runtime::Requirement)) : IR::Expr
          value = translate_value(check.value, requirements)
          if @types.carrier?(check.union)
            IR::Binary.new(IR::Selector.new(value, "tag"), "!=", IR::IntLit.new(@types.nil_tag(check.union).to_s))
          else
            IR::Binary.new(value, "!=", IR::Ident.new("nil"))
          end
        end

        private def payload_field(union : Tango::IR::Type, member : Tango::IR::Type) : String
          @types.payload_field(union, member)
        end
      end
    end
  end
end
