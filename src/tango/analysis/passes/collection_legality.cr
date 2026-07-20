module Tango
  module Analysis
    module Passes
      # Describes the evidence a later strategy would need before changing an
      # eager semantic chain. It deliberately never computes a "fusible" bool.
      class CollectionLegality
        private record SourceProperties,
          order : Facts::EncounterOrder,
          replayability : Facts::Replayability,
          finiteness : Facts::Finiteness,
          cardinality : Facts::CardinalityBounds

        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          @table = table
          @graph = CollectionGraphIndex.new(program, table)
          IR::NIR::Walk.children(program).each { |node| visit(node) }
        end

        @table = Facts::Table.new
        @graph : CollectionGraphIndex?
        @effects = Set(Facts::CollectionBlockEffect).new
        @may_raise = false
        @captured_mutation = false
        @abrupt_control_flow = false

        private def visit(node : IR::NIR::Stmt) : Nil
          IR::NIR::Walk.children(node).each { |child| visit(child) }
          operation = node.as?(IR::NIR::SemanticCollectionOperation)
          return unless operation

          graph = @graph
          return unless graph
          source = source_properties(operation.source, graph)
          escapes = operation.type.try(&.array?) ? graph.intermediate_escapes?(operation) : false
          @table.semantic_collections[operation.id] = Facts::SemanticCollectionFacts.new(
            escapes,
            block_behavior(operation.block),
            source.order,
            source.replayability,
            source.finiteness,
            source.cardinality,
            output_cardinality(operation, source.cardinality)
          )
        end

        private def source_properties(source : IR::NIR::Expr, graph : CollectionGraphIndex) : SourceProperties
          if producer = graph.producer(source)
            if facts = @table.semantic_collections[producer.id]?
              cardinality = if facts.intermediate_escapes
                              Facts::CardinalityBounds.new(0_i64, nil)
                            else
                              facts.output_cardinality || unknown_cardinality
                            end
              # Map/filter results are eager Arrays. Once produced, their
              # encounter order is stable and the value is finite/replayable.
              return SourceProperties.new(
                Facts::EncounterOrder::Stable,
                Facts::Replayability::Replayable,
                Facts::Finiteness::Finite,
                cardinality
              )
            end
          end

          type = source.type
          if type.try(&.array?)
            return SourceProperties.new(
              Facts::EncounterOrder::Stable,
              Facts::Replayability::Replayable,
              Facts::Finiteness::Finite,
              cardinality(source, graph, Set(NodeId).new)
            )
          end

          if type && type.name == "Range"
            end_type = type.type_args[1]?
            finiteness = end_type.try(&.nil_type?) ? Facts::Finiteness::Infinite : Facts::Finiteness::Finite
            return SourceProperties.new(
              Facts::EncounterOrder::Stable,
              Facts::Replayability::Replayable,
              finiteness,
              Facts::CardinalityBounds.new(0_i64, nil)
            )
          end

          SourceProperties.new(
            Facts::EncounterOrder::Unknown,
            Facts::Replayability::Unknown,
            Facts::Finiteness::Unknown,
            unknown_cardinality
          )
        end

        private def cardinality(expr : IR::NIR::Expr, graph : CollectionGraphIndex, seen : Set(NodeId)) : Facts::CardinalityBounds
          if producer = graph.producer(expr)
            if facts = @table.semantic_collections[producer.id]?
              return facts.output_cardinality || unknown_cardinality
            end
          end

          case expr
          when IR::NIR::Local
            declaration = graph.declaration(expr)
            if declaration && seen.add?(declaration)
              if graph.binding_confined_to_collection_reads?(declaration) && (value = graph.assigned_value(declaration))
                return cardinality(value, graph, seen)
              end
            end
          when IR::NIR::ArrayNew
            return Facts::CardinalityBounds.exact(0_i64)
          when IR::NIR::ArrayBuild
            if size = integer_literal(expr.size)
              return Facts::CardinalityBounds.exact(size) if size >= 0
            end
          when IR::NIR::ValueSequence
            if size = array_build_size(expr)
              return Facts::CardinalityBounds.exact(size)
            end
          end

          expr.type.try(&.array?) ? Facts::CardinalityBounds.new(0_i64, nil) : unknown_cardinality
        end

        private def array_build_size(node : IR::NIR::Stmt) : Int64?
          if build = node.as?(IR::NIR::ArrayBuild)
            size = integer_literal(build.size)
            return size if size && size >= 0
          end
          IR::NIR::Walk.children(node).each do |child|
            array_build_size(child).try { |size| return size }
          end
          nil
        end

        private def integer_literal(expr : IR::NIR::Expr) : Int64?
          literal = expr.as?(IR::NIR::IntLiteral)
          literal.try(&.value.to_i64?)
        end

        private def output_cardinality(operation : IR::NIR::SemanticCollectionOperation, input : Facts::CardinalityBounds) : Facts::CardinalityBounds?
          case operation
          when IR::NIR::CollectionMap
            input
          when IR::NIR::CollectionFilter
            maximum = input.maximum
            maximum == 0 ? Facts::CardinalityBounds.exact(0_i64) : Facts::CardinalityBounds.new(0_i64, maximum)
          when IR::NIR::CollectionEach, IR::NIR::CollectionFold
            nil
          end
        end

        private def unknown_cardinality : Facts::CardinalityBounds
          Facts::CardinalityBounds.new(nil, nil)
        end

        private def block_behavior(block : IR::NIR::BlockLiteral) : Facts::CollectionBlockBehavior
          @effects = Set(Facts::CollectionBlockEffect).new
          @may_raise = false
          @captured_mutation = false
          @abrupt_control_flow = false
          captures = @table.blocks[block.id]?.try(&.captured.map(&.declaration).to_set) || Set(NodeId).new
          inspect_block_node(block.body, captures)

          Facts::CollectionBlockBehavior.new(
            @effects.to_a.sort_by(&.value),
            @may_raise,
            @captured_mutation,
            @abrupt_control_flow
          )
        end

        private def inspect_block_node(node : IR::NIR::Stmt, captures : Set(NodeId)) : Nil
          case node
          when IR::NIR::Def, IR::NIR::BlockLiteral
            return # nested callable bodies do not execute merely by being made
          when IR::NIR::Assign
            inspect_assignment(node, captures)
            inspect_block_node(node.value, captures)
            return
          when IR::NIR::Call
            inspect_call(node)
            node.args.each { |arg| inspect_block_node(arg, captures) }
            return
          when IR::NIR::SemanticCollectionOperation
            add_effect(Facts::CollectionBlockEffect::Call)
            @may_raise = true
            node.fallback.args.each { |arg| inspect_block_node(arg, captures) }
            return
          when IR::NIR::InvokeBlock, IR::NIR::New
            add_effect(Facts::CollectionBlockEffect::Call)
            @may_raise = true
          when IR::NIR::Raise
            @may_raise = true
          when IR::NIR::Return, IR::NIR::Break, IR::NIR::Next
            @abrupt_control_flow = true
          when IR::NIR::ArraySet, IR::NIR::ArrayPush, IR::NIR::HashSet
            add_effect(Facts::CollectionBlockEffect::CollectionMutation)
            @may_raise = true
          when IR::NIR::ArrayGet, IR::NIR::HashGet, IR::NIR::HashFetch, IR::NIR::HashKeyAt, IR::NIR::StringCharAt
            @may_raise = true
          when IR::NIR::StringToInteger
            @may_raise = true
          when IR::NIR::Spawn, IR::NIR::ChannelOp, IR::NIR::Select
            add_effect(Facts::CollectionBlockEffect::Concurrency)
            @may_raise = true
          when IR::NIR::UnsupportedExpr
            add_effect(Facts::CollectionBlockEffect::Unknown)
            @may_raise = true
          end

          IR::NIR::Walk.children(node).each { |child| inspect_block_node(child, captures) }
        end

        private def inspect_assignment(node : IR::NIR::Assign, captures : Set(NodeId)) : Nil
          case target = node.target
          when IR::NIR::InstanceVar
            add_effect(Facts::CollectionBlockEffect::InstanceMutation)
          when IR::NIR::Local
            reference = @table.references[target.id]?
            captured = reference.is_a?(Facts::LocalReference) && captures.includes?(reference.declaration)
            if captured
              add_effect(Facts::CollectionBlockEffect::CapturedMutation)
              @captured_mutation = true
            else
              add_effect(Facts::CollectionBlockEffect::LocalMutation)
            end
          end
        end

        private def inspect_call(node : IR::NIR::Call) : Nil
          primitive = node.primitive
          unless primitive
            add_effect(Facts::CollectionBlockEffect::Call)
            @may_raise = true
            return
          end

          case primitive.kind
          when IR::NIR::Primitive::Kind::CheckedAdd,
               IR::NIR::Primitive::Kind::CheckedSub,
               IR::NIR::Primitive::Kind::CheckedMul,
               IR::NIR::Primitive::Kind::CheckedNegate,
               IR::NIR::Primitive::Kind::CheckedIntegerConvert,
               IR::NIR::Primitive::Kind::CheckedFloatConvert,
               IR::NIR::Primitive::Kind::IntegerPower,
               IR::NIR::Primitive::Kind::FloorDiv,
               IR::NIR::Primitive::Kind::FloorMod
            @may_raise = true
          end
        end

        private def add_effect(effect : Facts::CollectionBlockEffect) : Nil
          @effects << effect
        end
      end
    end
  end
end
