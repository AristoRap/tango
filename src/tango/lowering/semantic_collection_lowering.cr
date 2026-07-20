module Tango
  module Lowering
    module SemanticCollectionLowering
      private def lower_semantic_collection(node : IR::NIR::SemanticCollectionOperation, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        case plans.semantic_collections[node.id]?
        when Planning::Plans::MaterializeViaFallback
          lower_call_value(node.fallback, facts, plans)
        when Planning::Plans::FusedCollectionTraversal
          lower_fused_collection(node, facts, plans)
        else
          IR::LIR::UnsupportedValue.new("unplanned semantic collection operation #{node.class.name}", loc(node.span))
        end
      end

      private def lower_fused_collection(node : IR::NIR::SemanticCollectionOperation, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        plan = plans.semantic_collections[node.id].as(Planning::Plans::FusedCollectionTraversal)
        if each = node.as?(IR::NIR::CollectionEach)
          return lower_streamed_split_each(each, plan, facts, plans)
        end

        fold = node.as?(IR::NIR::CollectionFold) || raise "fused collection terminal is not a fold"
        map = fold.source.as?(IR::NIR::CollectionMap) || raise "fused collection is missing its map transform"
        filter = map.source.as?(IR::NIR::CollectionFilter) || raise "fused collection is missing its filter transform"
        source = filter.source
        raise "fused collection source does not match its plan" unless source.id == plan.source
        expected = plan.transforms.map(&.operation)
        raise "fused collection transforms do not match their plan" unless expected == [filter.id, map.id]

        element = source.type.try(&.element_type) || IR::Type.unknown
        lir_source = IR::LIR::ArrayElements.new(lower_value(source, facts, plans), element)
        transforms = [
          IR::LIR::CollectionFilterTransform.new(lower_block_literal(filter.block, facts, plans).as(IR::LIR::Closure)).as(IR::LIR::CollectionTransform),
          IR::LIR::CollectionMapTransform.new(lower_block_literal(map.block, facts, plans).as(IR::LIR::Closure)).as(IR::LIR::CollectionTransform),
        ]
        terminal = IR::LIR::CollectionFoldTerminal.new(
          lower_operand(fold.initial, plan.result_type, facts, plans),
          lower_block_literal(fold.block, facts, plans).as(IR::LIR::Closure),
          plan.result_type
        )
        IR::LIR::FusedCollectionTraversal.new(lir_source, transforms, terminal, plan.result_type)
      end

      private def lower_streamed_split_each(node : IR::NIR::CollectionEach, plan : Planning::Plans::FusedCollectionTraversal, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::FusedCollectionTraversal
        split = node.source.as?(IR::NIR::StringSplit) || raise "streamed collection source is not a string split"
        raise "streamed collection source does not match its plan" unless split.id == plan.source
        raise "streamed string split unexpectedly has transforms" unless plan.transforms.empty?
        production = plans.collection_productions[split.id]?
        raise "streamed string split has no streamed production plan" unless production.is_a?(Planning::Plans::StreamedCollection)
        separator = split.separator || raise "streamed string split has no separator"
        source = IR::LIR::StringSegments.new(
          lower_value(split.string, facts, plans),
          lower_value(separator, facts, plans)
        )
        terminal = IR::LIR::CollectionEachTerminal.new(lower_block_literal(node.block, facts, plans).as(IR::LIR::Closure))
        IR::LIR::FusedCollectionTraversal.new(source, [] of IR::LIR::CollectionTransform, terminal, plan.result_type)
      end
    end
  end
end
