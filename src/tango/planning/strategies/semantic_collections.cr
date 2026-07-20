module Tango
  module Planning
    module Strategies
      # Development preserves ordinary eager behavior. Release admits the one
      # benchmark-backed select/map/fold traversal only from analysis-owned
      # laws and graph edges; profile policy enters here, never upstream.
      class SemanticCollections
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table, profile : Compiler::CompilationProfile = Compiler::CompilationProfile::Development) : Nil
          IR::NIR::Walk.children(program).each { |node| visit(node, facts, table, profile) }
        end

        private def self.visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table, profile : Compiler::CompilationProfile) : Nil
          IR::NIR::Walk.children(node).each { |child| visit(child, facts, table, profile) }
          if node.is_a?(IR::NIR::SemanticCollectionOperation) && (type = node.type)
            plan = profile.release? ? fused_plan(node, facts, table, type) : nil
            table.semantic_collections[node.id] = plan || Plans::MaterializeViaFallback.new(type)
          end
        end

        private def self.fused_plan(operation : IR::NIR::SemanticCollectionOperation, facts : Analysis::Facts::Table, table : Plans::Table, result_type : IR::Type) : Plans::FusedCollectionTraversal?
          if each = operation.as?(IR::NIR::CollectionEach)
            if split = each.source.as?(IR::NIR::StringSplit)
              if table.collection_productions[split.id]?.is_a?(Plans::StreamedCollection)
                return Plans::FusedCollectionTraversal.new(result_type, split.id, [] of Plans::FusedCollectionTransform, each.id)
              end
            end
          end

          fold = operation.as?(IR::NIR::CollectionFold)
          return nil unless fold
          map = fold.source.as?(IR::NIR::CollectionMap)
          return nil unless map
          filter = map.source.as?(IR::NIR::CollectionFilter)
          return nil unless filter && filter.mode.keep?
          source = filter.source
          return nil unless source.type.try(&.array?)
          return nil unless direct_only_use?(filter, map, Analysis::Facts::CollectionConsumer::Map, facts)
          return nil unless direct_only_use?(map, fold, Analysis::Facts::CollectionConsumer::Fold, facts)
          return nil unless transform_safe?(filter, facts)
          return nil unless transform_safe?(map, facts)
          return nil unless terminal_safe?(fold, facts)

          transforms = [
            Plans::FusedCollectionTransform.new(filter.id, Plans::FusedCollectionTransformKind::FilterKeep),
            Plans::FusedCollectionTransform.new(map.id, Plans::FusedCollectionTransformKind::Map),
          ]
          Plans::FusedCollectionTraversal.new(result_type, source.id, transforms, fold.id)
        end

        private def self.direct_only_use?(producer : IR::NIR::SemanticCollectionOperation, consumer : IR::NIR::SemanticCollectionOperation, kind : Analysis::Facts::CollectionConsumer, facts : Analysis::Facts::Table) : Bool
          uses = facts.collection_uses[producer.id]?
          return false unless uses && uses.size == 1
          uses.first == Analysis::Facts::CollectionUse.new(consumer.id, kind, Analysis::Facts::CollectionUsePath::Direct)
        end

        private def self.transform_safe?(operation : IR::NIR::SemanticCollectionOperation, facts : Analysis::Facts::Table) : Bool
          evidence = facts.semantic_collections[operation.id]?
          return false unless evidence && common_laws?(evidence)
          !evidence.block.may_raise
        end

        private def self.terminal_safe?(operation : IR::NIR::SemanticCollectionOperation, facts : Analysis::Facts::Table) : Bool
          evidence = facts.semantic_collections[operation.id]?
          evidence ? common_laws?(evidence) : false
        end

        private def self.common_laws?(evidence : Analysis::Facts::SemanticCollectionFacts) : Bool
          block = evidence.block
          !evidence.intermediate_escapes &&
            evidence.encounter_order.stable? &&
            evidence.replayability.replayable? &&
            evidence.finiteness.finite? &&
            block.effects.empty? &&
            !block.captured_mutation &&
            !block.abrupt_control_flow
        end
      end
    end
  end
end
