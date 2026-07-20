module Tango
  module Analysis
    module Passes
      # Records laws only for structured traversal operations whose contracts
      # provide direct evidence. Merely including Iterator or Enumerable does
      # not synthesize Array-like order, finiteness, or replayability.
      class Traversals
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          program.body.each { |node| visit(node, table) }
        end

        private def visit(node : IR::NIR::Stmt, table : Facts::Table) : Nil
          if node.is_a?(IR::NIR::ChannelOp) && node.kind.next_state?
            table.traversals[node.id] = Facts::TraversalFacts.new(
              Facts::BlockingBehavior::MayBlock,
              Facts::ConsumptionBehavior::Destructive,
              Facts::Replayability::OneShot,
              Facts::Finiteness::Unknown,
              Facts::EncounterOrder::Unknown
            )
          end
          IR::NIR::Walk.non_binding_children(node).each { |child| visit(child, table) }
        end
      end
    end
  end
end
