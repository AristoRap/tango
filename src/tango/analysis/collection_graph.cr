module Tango
  module Analysis
    # Shared value-flow view used by collection fact passes. It follows only
    # unambiguous local aliases; reassigned bindings stay unknown rather than
    # manufacturing a producer edge.
    class CollectionGraphIndex
      getter nodes = [] of IR::NIR::Stmt

      def initialize(program : IR::NIR::Program, @facts : Facts::Table)
        @parents = Hash(NodeId, IR::NIR::Stmt).new
        @assigned_values = Hash(NodeId, Array(IR::NIR::Expr)).new
        IR::NIR::Walk.children(program).each { |node| collect(node, nil) }
      end

      def parent(node : IR::NIR::Stmt) : IR::NIR::Stmt?
        @parents[node.id]?
      end

      def assigned_value(declaration : NodeId) : IR::NIR::Expr?
        values = @assigned_values[declaration]?
        return nil unless values && values.size == 1
        values.first
      end

      def declaration(local : IR::NIR::Local) : NodeId?
        reference = @facts.references[local.id]?
        reference.declaration if reference.is_a?(Facts::LocalReference)
      end

      # Exact cardinality may follow a local initializer only while every read
      # stays in a semantic traversal/size position. An opaque read could
      # mutate the reference before a later consumer, so it invalidates proof.
      def binding_confined_to_collection_reads?(declaration : NodeId) : Bool
        nodes.all? do |node|
          local = node.as?(IR::NIR::Local)
          next true unless local && self.declaration(local) == declaration
          parent = self.parent(local)
          case parent
          when IR::NIR::SemanticCollectionOperation
            parent.source.id == local.id
          when IR::NIR::Size
            parent.value.id == local.id
          else
            false
          end
        end
      end

      def producer(expr : IR::NIR::Expr) : IR::NIR::SemanticCollectionOperation?
        producer(expr, Set(NodeId).new)
      end

      def use_path(expr : IR::NIR::Expr) : Facts::CollectionUsePath?
        found = producer(expr)
        return nil unless found
        expr.is_a?(IR::NIR::SemanticCollectionOperation) ? Facts::CollectionUsePath::Direct : Facts::CollectionUsePath::Aliased
      end

      def collection_producers : Array(IR::NIR::SemanticCollectionOperation)
        nodes.compact_map do |node|
          operation = node.as?(IR::NIR::SemanticCollectionOperation)
          operation if operation && operation.type.try(&.array?)
        end
      end

      def intermediate_escapes?(producer : IR::NIR::SemanticCollectionOperation) : Bool
        nodes.any? do |node|
          expr = node.as?(IR::NIR::Expr)
          next false unless expr && self.producer(expr) == producer
          !safe_collection_use?(expr, parent(expr))
        end
      end

      private def producer(expr : IR::NIR::Expr, seen : Set(NodeId)) : IR::NIR::SemanticCollectionOperation?
        if operation = expr.as?(IR::NIR::SemanticCollectionOperation)
          return operation if operation.type.try(&.array?)
        end
        return nil unless local = expr.as?(IR::NIR::Local)
        declaration = declaration(local)
        return nil unless declaration && seen.add?(declaration)
        value = assigned_value(declaration)
        value ? producer(value, seen) : nil
      end

      private def collect(node : IR::NIR::Stmt, parent : IR::NIR::Stmt?) : Nil
        nodes << node
        @parents[node.id] = parent if parent

        if assignment = node.as?(IR::NIR::Assign)
          if target = assignment.target.as?(IR::NIR::Local)
            declaration = @facts.local_writes[target.id]? || target.id
            values = @assigned_values[declaration] ||= [] of IR::NIR::Expr
            values << assignment.value
          end
        end

        IR::NIR::Walk.children(node).each { |child| collect(child, node) }
      end

      private def safe_collection_use?(expr : IR::NIR::Expr, parent : IR::NIR::Stmt?) : Bool
        return true unless parent
        case parent
        when IR::NIR::Assign
          return false unless parent.value.id == expr.id
          target = parent.target.as?(IR::NIR::Local)
          return false unless target
          declaration = @facts.local_writes[target.id]? || target.id
          values = @assigned_values[declaration]?
          values ? values.size == 1 : false
        when IR::NIR::SemanticCollectionOperation
          parent.source.id == expr.id
        when IR::NIR::Size
          parent.value.id == expr.id
        when IR::NIR::Block
          true # evaluated and discarded, not exposed to another consumer
        else
          false
        end
      end
    end
  end
end
