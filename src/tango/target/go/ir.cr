module Tango
  module Target
    module Go
      module IR
        class File
          getter package_name : String
          getter requirements : Array(Runtime::Requirement)
          getter functions : Array(Func)
          getter struct_decls : Array(StructDecl)
          getter method_decls : Array(MethodDecl)
          getter enum_decls : Array(EnumDecl)

          def initialize(@package_name : String, @requirements : Array(Runtime::Requirement), @functions : Array(Func), @struct_decls : Array(StructDecl) = [] of StructDecl, @method_decls : Array(MethodDecl) = [] of MethodDecl, @enum_decls : Array(EnumDecl) = [] of EnumDecl)
          end
        end

        class EnumDecl
          record Member, name : String, value : String

          getter name : String
          getter base_type : String
          getter members : Array(Member)

          def initialize(@name : String, @base_type : String, @members : Array(Member))
          end
        end

        class StructDecl
          record Field, name : String, type_name : String

          getter name : String
          getter fields : Array(Field)

          def initialize(@name : String, @fields : Array(Field))
          end
        end

        class Param
          getter name : String
          getter type_name : String

          def initialize(@name : String, @type_name : String)
          end
        end

        class Func
          record Receiver, name : String, type_name : String

          getter name : String
          getter params : Array(Param)
          getter return_type : String?
          getter body : Array(Stmt)
          getter line : LineDirective?
          getter receiver : Receiver?

          def initialize(@name : String, @body : Array(Stmt), @params : Array(Param) = [] of Param, @return_type : String? = nil, @line : LineDirective? = nil, @receiver : Receiver? = nil)
          end
        end

        # A named Go method declaration. It reuses Func's typed callable body
        # and signature while remaining a distinct declaration node in File,
        # so generated methods are explicit rather than inferred during source
        # emission from a receiver-bearing free-function entry.
        class MethodDecl < Func
          def initialize(name : String, receiver : Receiver, body : Array(Stmt), return_type : String? = nil)
            super(name, body, return_type: return_type, receiver: receiver)
          end
        end

        abstract class Stmt
        end

        class LineDirective < Stmt
          getter file : String
          getter line : Int32
          getter column : Int32

          def initialize(@file : String, @line : Int32, @column : Int32)
          end
        end

        class ReturnStmt < Stmt
          getter value : Expr?

          def initialize(@value : Expr?)
          end
        end

        class ExprStmt < Stmt
          getter expr : Expr

          def initialize(@expr : Expr)
          end
        end

        class AssignStmt < Stmt
          enum Mode
            Declare
            Reassign
          end

          getter target : Expr
          getter mode : Mode
          getter value : Expr

          def initialize(@target : Expr, @mode : Mode, @value : Expr)
          end
        end

        class MultiAssignStmt < Stmt
          getter targets : Array(Expr)
          getter mode : AssignStmt::Mode
          getter values : Array(Expr)

          def initialize(@targets : Array(Expr), @mode : AssignStmt::Mode, @values : Array(Expr))
          end
        end

        class VarDecl < Stmt
          getter target : String
          getter type_name : String

          def initialize(@target : String, @type_name : String)
          end
        end

        class IfStmt < Stmt
          getter cond : Expr
          getter then_body : Array(Stmt)
          getter else_body : Array(Stmt)

          def initialize(@cond : Expr, @then_body : Array(Stmt), @else_body : Array(Stmt))
          end
        end

        class DeferStmt < Stmt
          getter call : Expr

          def initialize(@call : Expr)
          end
        end

        class BranchStmt < Stmt
          enum Kind
            Break
            Continue
          end

          getter kind : Kind

          def initialize(@kind : Kind)
          end
        end

        # Go has no `while` keyword — a condition-only `for` is its native
        # spelling of one.
        class ForStmt < Stmt
          getter cond : Expr?
          getter body : Array(Stmt)

          def initialize(@cond : Expr?, @body : Array(Stmt))
          end
        end

        # A typed value-range loop. Collection traversal lowering has already
        # selected this mechanism; the source printer only spells it.
        class RangeStmt < Stmt
          getter value_ident : String
          getter source : Expr
          getter body : Array(Stmt)

          def initialize(@value_ident : String, @source : Expr, @body : Array(Stmt))
          end
        end

        # `ch <- value`.
        class SendStmt < Stmt
          getter channel : Expr
          getter value : Expr

          def initialize(@channel : Expr, @value : Expr)
          end
        end

        # `go call` — a goroutine launch. `call` is the invocation expression.
        class GoStmt < Stmt
          getter call : Expr

          def initialize(@call : Expr)
          end
        end

        # `select { case ...: ...; default: ... }`. Each clause's comm is a
        # receive binding (`value, ok := <-channel`, `value := <-channel`, or a
        # bare `<-channel`) or a send (`channel <- send_value`); a nil `default`
        # is a blocking select.
        class SelectStmt < Stmt
          class Clause
            getter channel : Expr
            getter send_value : Expr?
            getter value_ident : String
            getter ok_ident : String
            getter body : Array(Stmt)

            def initialize(@channel : Expr, @send_value : Expr?, @value_ident : String, @ok_ident : String, @body : Array(Stmt))
            end
          end

          getter clauses : Array(Clause)
          getter default : Array(Stmt)?

          def initialize(@clauses : Array(Clause), @default : Array(Stmt)? = nil)
          end
        end

        # `switch value { case label: ...; default: ... }`. A nil case label is
        # the typed representation of `default`; clause bodies remain ordinary
        # typed statements.
        class Switch < Stmt
          class Case
            getter label : Expr?
            getter body : Array(Stmt)

            def initialize(@label : Expr?, @body : Array(Stmt))
            end
          end

          getter value : Expr
          getter cases : Array(Case)

          def initialize(@value : Expr, @cases : Array(Case))
          end
        end

        abstract class Expr
        end

        class Ident < Expr
          getter name : String

          def initialize(@name : String)
          end
        end

        class IntLit < Expr
          getter value : String

          def initialize(@value : String)
          end
        end

        class FloatLit < Expr
          getter value : String

          def initialize(@value : String)
          end
        end

        class StringLit < Expr
          getter value : String

          def initialize(@value : String)
          end
        end

        class BoolLit < Expr
          getter value : Bool

          def initialize(@value : Bool)
          end
        end

        class Selector < Expr
          getter receiver : Expr
          getter name : String

          def initialize(@receiver : Expr, @name : String)
          end
        end

        class Call < Expr
          getter callee : Expr
          getter args : Array(Expr)

          def initialize(@callee : Expr, @args : Array(Expr))
          end
        end

        # A generic function instantiation such as `f[int32]`, kept distinct
        # from Ident so type arguments cannot be smuggled through a name string.
        class GenericInst < Expr
          getter callee : Expr
          getter type_args : Array(String)

          def initialize(@callee : Expr, @type_args : Array(String))
          end
        end

        class Deref < Expr
          getter expr : Expr

          def initialize(@expr : Expr)
          end
        end

        class Index < Expr
          getter receiver : Expr
          getter index : Expr

          def initialize(@receiver : Expr, @index : Expr)
          end
        end

        class TypeAssert < Expr
          getter value : Expr
          getter type_name : String

          def initialize(@value : Expr, @type_name : String)
          end
        end

        class Binary < Expr
          getter left : Expr
          getter operator : String
          getter right : Expr

          def initialize(@left : Expr, @operator : String, @right : Expr)
          end
        end

        # `!expr` — boolean negation.
        class Not < Expr
          getter expr : Expr

          def initialize(@expr : Expr)
          end
        end

        # `^expr` — Go's bitwise complement spelling.
        class BitNot < Expr
          getter expr : Expr

          def initialize(@expr : Expr)
          end
        end

        # A composite literal `Type{}` or `Type{f1: v1, f2: v2}`. With no fields
        # the members are left zero (the constructor assigns them, or — for a
        # carrier's nil variant — zero IS the value). `&Type{}` is this wrapped
        # in an AddrOf.
        class CompositeLit < Expr
          getter type_name : String
          getter fields : Array(Tuple(String, Expr))

          def initialize(@type_name : String, @fields : Array(Tuple(String, Expr)) = [] of Tuple(String, Expr))
          end
        end

        class AddrOf < Expr
          getter expr : Expr

          def initialize(@expr : Expr)
          end
        end

        # `<-ch` — a receive expression.
        class RecvExpr < Expr
          getter channel : Expr

          def initialize(@channel : Expr)
          end
        end

        # `make(chan T)` or `make(chan T, capacity)`.
        class MakeChan < Expr
          getter element_type : String
          getter capacity : Expr?

          def initialize(@element_type : String, @capacity : Expr? = nil)
          end
        end

        class FuncLit < Expr
          getter params : Array(Param)
          getter return_type : String?
          getter body : Array(Stmt)

          def initialize(@params : Array(Param), @return_type : String?, @body : Array(Stmt))
          end
        end
      end
    end
  end
end
