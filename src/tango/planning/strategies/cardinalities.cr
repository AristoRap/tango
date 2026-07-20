module Tango
  module Planning
    module Strategies
      # Chooses a realization for the shared semantic Size operation from the
      # receiver type already recorded by analysis.
      class Cardinalities
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          IR::NIR::Walk.children(program).each { |node| visit(node, facts, table) }
        end

        private def visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          if node.is_a?(IR::NIR::Size) && (source_type = facts.types.expressions[node.value.id]?)
            plan = case source_type.family
                   when .array?
                     Plans::StoredCardinality.new(source_type, Plans::StoredCardinality::Source::ArrayElements)
                   when .hash?
                     Plans::StoredCardinality.new(source_type, Plans::StoredCardinality::Source::HashEntries)
                   when .string?
                     Plans::CodepointCardinality.new(source_type)
                   end
            table.cardinalities[node.id] = plan if plan
          end

          IR::NIR::Walk.children(node).each { |child| visit(child, facts, table) }
        end
      end
    end
  end
end
