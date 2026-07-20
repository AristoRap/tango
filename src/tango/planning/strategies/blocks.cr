module Tango
  module Planning
    module Strategies
      class Blocks
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          program.body.each { |stmt| visit(stmt, facts, table) }
        end

        private def visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          call = case node
                 when IR::NIR::Call                        then node
                 when IR::NIR::SemanticCollectionOperation then node.fallback
                 end
          if call && (literal = call.block) && facts.blocks.has_key?(literal.id)
            mode = facts.internal_calls[node.id]?.try do |resolved|
              table.monomorphs[resolved.definition]?.try(&.block_mode)
            end || block_mode(literal.signature)
            table.closures[literal.id] = Plans::ClosurePlan.new(mode)
          elsif node.is_a?(IR::NIR::StringEachChar) && facts.blocks.has_key?(node.block.id)
            # `each_char` is a yield-style iteration boundary: break/next use
            # the shared protocol already chosen for Array/Hash iteration.
            table.closures[node.block.id] = Plans::ClosurePlan.new(Plans::BlockMode.for_yield(false))
          end

          IR::NIR::Walk.children(node).each { |child| visit(child, facts, table) }
        end

        private def block_mode(signature : IR::NIR::ProcSignature) : Plans::BlockMode
          signature.return_type ? Plans::BlockMode::Value : Plans::BlockMode::Plain
        end
      end
    end
  end
end
