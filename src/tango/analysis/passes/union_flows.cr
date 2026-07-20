module Tango
  module Analysis
    module Passes
      # Records strict union-subset value flows at typed slot boundaries. The
      # frontend already supplied both resolved types; this pass neither infers
      # types nor chooses a representation/conversion strategy.
      class UnionFlows
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          definitions = {} of NodeId => IR::NIR::Def
          program.body.each do |stmt|
            definitions[stmt.id] = stmt if stmt.is_a?(IR::NIR::Def)
          end
          program.body.each { |stmt| visit(stmt, nil, definitions, table) }
        end

        private def visit(node : IR::NIR::Stmt, expected : IR::Type?, definitions : Hash(NodeId, IR::NIR::Def), table : Facts::Table) : Nil
          record(node, expected, table) if node.is_a?(IR::NIR::Expr)

          case node
          when IR::NIR::Def
            visit_block(node.body, node.return_type, definitions, table)
          when IR::NIR::Block
            visit_block(node, expected, definitions, table)
          when IR::NIR::Assign
            visit(node.value, node.target.type, definitions, table)
          when IR::NIR::If
            visit(node.cond, nil, definitions, table)
            visit_block(node.then_branch, node.type, definitions, table)
            node.else_branch.try { |branch| visit_block(branch, node.type, definitions, table) }
          when IR::NIR::Call, IR::NIR::SemanticOperation
            call = node.is_a?(IR::NIR::Call) ? node : node.fallback
            definition = table.internal_calls[node.id]?.try { |resolved| definitions[resolved.definition]? }
            call.args.each_with_index do |arg, index|
              visit(arg, definition.try(&.params[index]?.try(&.type)), definitions, table)
            end
            call.block.try { |block| visit(block, nil, definitions, table) }
          when IR::NIR::BlockLiteral
            visit_block(node.body, node.signature.return_type, definitions, table)
          when IR::NIR::ValueSequence
            visit_block(node.prefix, nil, definitions, table)
            visit(node.value, node.type, definitions, table)
          when IR::NIR::ExceptionHandler
            visit_block(node.body, node.type, definitions, table)
            node.clauses.each { |clause| visit_block(clause.body, node.type, definitions, table) }
            node.else_branch.try { |branch| visit_block(branch, node.type, definitions, table) }
            node.ensure_branch.try { |branch| visit_block(branch, nil, definitions, table) }
          else
            IR::NIR::Walk.non_binding_children(node).each { |child| visit(child, nil, definitions, table) }
          end
        end

        private def visit_block(block : IR::NIR::Block, expected : IR::Type?, definitions : Hash(NodeId, IR::NIR::Def), table : Facts::Table) : Nil
          block.body.each_with_index do |stmt, index|
            terminal = index == block.body.size - 1 && stmt.is_a?(IR::NIR::Expr)
            visit(stmt, terminal ? expected : nil, definitions, table)
          end
        end

        private def record(node : IR::NIR::Expr, expected : IR::Type?, table : Facts::Table) : Nil
          source = node.type
          return unless source && expected && source.union? && expected.union? && source != expected
          return unless source.members.all? { |member| expected.members.includes?(member) }

          table.union_flows[node.id] = Facts::UnionFlow.new(source, expected)
        end
      end
    end
  end
end
