module Tango
  module Analysis
    module Passes
      # Records producer/consumer edges and whether they pass directly or
      # through an unambiguous local alias. CollectionLegality separately
      # records observations outside this known consumer graph as escape.
      class CollectionUses
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          graph = CollectionGraphIndex.new(program, table)
          graph.nodes.each { |node| record_use(node, graph, table) }
        end

        private def record_use(node : IR::NIR::Stmt, graph : CollectionGraphIndex, table : Facts::Table) : Nil
          case node
          when IR::NIR::SemanticCollectionOperation
            record_semantic_use(node, graph, table)
          when IR::NIR::Size
            if producer = graph.producer(node.value)
              add_use(producer.id, node.id, Facts::CollectionConsumer::Size, graph.use_path(node.value) || Facts::CollectionUsePath::Direct, table)
            else
              add_use(node.value.id, node.id, Facts::CollectionConsumer::Size, Facts::CollectionUsePath::Direct, table)
            end
          end
        end

        private def record_semantic_use(node : IR::NIR::SemanticCollectionOperation, graph : CollectionGraphIndex, table : Facts::Table) : Nil
          producer = graph.producer(node.source) || node.source.as?(IR::NIR::StringSplit)
          return unless producer
          path = graph.use_path(node.source) || Facts::CollectionUsePath::Direct
          add_use(producer.id, node.id, consumer_kind(node), path, table)
        end

        private def consumer_kind(node : IR::NIR::SemanticCollectionOperation) : Facts::CollectionConsumer
          case node
          when IR::NIR::CollectionMap    then Facts::CollectionConsumer::Map
          when IR::NIR::CollectionFilter then Facts::CollectionConsumer::Filter
          when IR::NIR::CollectionEach   then Facts::CollectionConsumer::Each
          when IR::NIR::CollectionFold   then Facts::CollectionConsumer::Fold
          else                                raise ArgumentError.new("unknown semantic collection consumer #{node.class.name}")
          end
        end

        private def add_use(producer : NodeId, consumer : NodeId, kind : Facts::CollectionConsumer, path : Facts::CollectionUsePath, table : Facts::Table) : Nil
          uses = table.collection_uses[producer] ||= [] of Facts::CollectionUse
          use = Facts::CollectionUse.new(consumer, kind, path)
          uses << use unless uses.includes?(use)
        end
      end
    end
  end
end
