module Tango
  module Planning
    module Strategies
      # Development preserves ordinary eager behavior. Release currently
      # streams only String#split into each. Array select/map/fold fusion stays
      # disabled: interleaving stages changes exception order unless every
      # executable NIR node has conservative, exhaustive effect evidence.
      class SemanticCollections
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table, profile : Compiler::CompilationProfile = Compiler::CompilationProfile::Development) : Nil
          IR::NIR::Walk.children(program).each { |node| visit(node, facts, table, profile) }
        end

        private def self.visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table, profile : Compiler::CompilationProfile) : Nil
          IR::NIR::Walk.children(node).each { |child| visit(child, facts, table, profile) }
          if node.is_a?(IR::NIR::SemanticCollectionOperation) && (type = node.type)
            plan = profile.release? ? streamed_plan(node, table, type) : nil
            table.semantic_collections[node.id] = plan || Plans::MaterializeViaFallback.new(type)
          end
        end

        private def self.streamed_plan(operation : IR::NIR::SemanticCollectionOperation, table : Plans::Table, result_type : IR::Type) : Plans::FusedCollectionTraversal?
          if each = operation.as?(IR::NIR::CollectionEach)
            if split = each.source.as?(IR::NIR::StringSplit)
              if table.collection_productions[split.id]?.is_a?(Plans::StreamedCollection)
                return Plans::FusedCollectionTraversal.new(result_type, split.id, [] of Plans::FusedCollectionTransform, each.id)
              end
            end
          end
          nil
        end
      end
    end
  end
end
