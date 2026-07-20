module Tango
  module Target
    module Go
      class FromLIR
        # User exception behavior is emitted as typed Go methods, never runtime
        # snippets: the planned exception metadata crossed on StructType, and
        # this target-only step merely spells that decision for the Go method
        # set required by tangoException.
        private def exception_runtime_functions(type : Tango::IR::LIR::StructType) : Array(IR::Func)
          return [] of IR::Func unless type.exception_runtime?

          receiver = IR::Func::Receiver.new("e", "*#{type.name}")
          is_a = type.exception_ancestors.map do |ancestor|
            IR::Binary.new(IR::Ident.new("name"), "==", IR::StringLit.new(ancestor)).as(IR::Expr)
          end.reduce do |left, right|
            IR::Binary.new(left, "||", right).as(IR::Expr)
          end
          [
            IR::Func.new("tangoExceptionMarker", [] of IR::Stmt, receiver: receiver),
            IR::Func.new(
              "tangoMessage",
              [IR::ReturnStmt.new(IR::Selector.new(IR::Ident.new("e"), "message")).as(IR::Stmt)],
              return_type: "string",
              receiver: receiver
            ),
            IR::Func.new(
              "tangoClass",
              [IR::ReturnStmt.new(IR::StringLit.new(type.name)).as(IR::Stmt)],
              return_type: "string",
              receiver: receiver
            ),
            IR::Func.new(
              "tangoIsA",
              [IR::ReturnStmt.new(is_a).as(IR::Stmt)],
              params: [IR::Param.new("name", "string")],
              return_type: "bool",
              receiver: receiver
            ),
            IR::Func.new(
              "Error",
              [IR::ReturnStmt.new(
                IR::Binary.new(
                  IR::Selector.new(IR::Ident.new("e"), "message"),
                  "+",
                  IR::StringLit.new(" (#{type.name})")
                )
              ).as(IR::Stmt)],
              return_type: "string",
              receiver: receiver
            ),
          ]
        end
      end
    end
  end
end
