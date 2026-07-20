module Tango
  module Planning
    module Strategies
      # Chooses how semantic collection producers are realized. Materialization
      # is conservative until analysis proves a narrower realization preserves
      # every observable use.
      class CollectionProductions
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table, profile : Compiler::CompilationProfile = Compiler::CompilationProfile::Development) : Nil
          new.run(program, facts, table, profile)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table, profile : Compiler::CompilationProfile) : Nil
          IR::NIR::Walk.children(program).each { |node| visit(node, facts, table, profile) }
        end

        private def visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table, profile : Compiler::CompilationProfile) : Nil
          if node.is_a?(IR::NIR::StringSplit) && (type = node.type)
            table.collection_productions[node.id] = streamed?(node, facts, profile) ? Plans::StreamedCollection.new(type) : Plans::MaterializedCollection.new(type)
          end
          IR::NIR::Walk.children(node).each { |child| visit(child, facts, table, profile) }
        end

        private def streamed?(node : IR::NIR::StringSplit, facts : Analysis::Facts::Table, profile : Compiler::CompilationProfile) : Bool
          return false unless profile.release?
          separator = node.separator.as?(IR::NIR::StringLiteral)
          return false unless separator && !separator.value.empty?
          uses = facts.collection_uses[node.id]?
          return false unless uses && uses.size == 1
          use = uses.first
          use.kind.each? && use.path.direct?
        end
      end
    end
  end
end
