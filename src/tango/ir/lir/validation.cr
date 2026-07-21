module Tango
  module IR
    module LIR
      # Reasons a program cannot proceed to codegen. Non-empty means the
      # pipeline must stop before target translation.
      record UnsupportedReason, message : String, loc : SourceLoc?

      def self.unsupported_reasons(program : Program) : Array(UnsupportedReason)
        reasons = [] of UnsupportedReason

        program.functions.each do |function|
          function.body.each { |stmt| unsupported_node_reasons(stmt, reasons) }
        end
        program.body.each { |stmt| unsupported_node_reasons(stmt, reasons) }
        program.globals.each { |global| unsupported_node_reasons(global.value, reasons) }

        reasons
      end

      private def self.unsupported_node_reasons(node : Walk::Node, reasons : Array(UnsupportedReason)) : Nil
        case node
        when UnsupportedStmt
          reasons << UnsupportedReason.new(node.reason, node.loc)
        when UnsupportedValue
          reasons << UnsupportedReason.new(node.reason, node.loc)
        when Stmt
          Walk.children(node).each { |child| unsupported_node_reasons(child, reasons) }
        when Value
          Walk.children(node).each { |child| unsupported_node_reasons(child, reasons) }
        end
      end
    end
  end
end
