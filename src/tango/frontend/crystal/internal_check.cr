module Tango
  module Frontend
    module Crystal
      # Rejects user-written calls to prelude definitions that exist solely for
      # Crystal's expansion machinery. Resolved target annotations establish
      # which typed calls are reserved; matching name/location pairs in the
      # unexpanded surface AST establish which calls the user actually wrote.
      module InternalCheck
        alias CallKey = Tuple(String, String)

        def self.run(
          program : ::Crystal::Program,
          typed : ::Crystal::ASTNode,
          surface : ::Crystal::ASTNode,
          source : Source::File,
        ) : Array(Diagnostic)
          annotation_diagnostics = reserved_annotation_diagnostics(surface, source)
          marker = program.types["TangoInternal"]?.as?(::Crystal::AnnotationType)
          return annotation_diagnostics unless marker

          surface_calls = collect_calls(surface).select do |call|
            call.location.try(&.filename) == source.path
          end
          reserved = reserved_call_keys(typed, marker, source.path)

          call_diagnostics = surface_calls.compact_map do |call|
            location = call.location
            next unless location && reserved.includes?({location.to_s, call.name})

            name_location = call.name_location || location
            line = name_location.line_number
            column = name_location.column_number
            size = call.name.bytesize
            Diagnostic.new(
              Diagnostic::Origin::Check,
              Diagnostic::Severity::Error,
              Diagnostics::INTERNAL_RESERVED,
              "#{call.name} is tango-internal expansion plumbing — not callable from user code",
              file: source.path,
              line: line,
              column: column,
              size: size,
              range: source.range_at(line, column, size)
            )
          end
          annotation_diagnostics + call_diagnostics
        end

        private def self.reserved_annotation_diagnostics(surface : ::Crystal::ASTNode, source : Source::File) : Array(Diagnostic)
          collect_annotations(surface).compact_map do |entry|
            next unless entry.path.names == ["TangoSemantic"]
            location = entry.path.location || entry.location
            next unless location

            name = "TangoSemantic"
            line = location.line_number
            column = location.column_number
            Diagnostic.new(
              Diagnostic::Origin::Check,
              Diagnostic::Severity::Error,
              Diagnostics::INTERNAL_RESERVED,
              "#{name} is a reserved prelude-only semantic annotation",
              file: source.path,
              line: line,
              column: column,
              size: name.bytesize,
              range: source.range_at(line, column, name.bytesize)
            )
          end
        end

        private def self.reserved_call_keys(
          typed : ::Crystal::ASTNode,
          marker : ::Crystal::AnnotationType,
          path : String,
        ) : Set(CallKey)
          reserved = Set(CallKey).new
          seen_defs = Set(UInt64).new
          queue = collect_calls(typed)

          while call = queue.shift?
            call.target_defs.try &.each do |definition|
              queue.concat(collect_calls(definition.body)) if seen_defs.add?(definition.object_id)
              next unless definition.annotation(marker)

              location = call.location
              next unless location && location.filename == path
              reserved << {location.to_s, call.name}
            end
          end

          reserved
        end

        private class CallCollector < ::Crystal::Visitor
          getter calls = [] of ::Crystal::Call

          def visit(node : ::Crystal::Call)
            @calls << node
            true
          end

          def visit(node : ::Crystal::ASTNode)
            true
          end
        end

        private class AnnotationCollector < ::Crystal::Visitor
          getter entries = [] of ::Crystal::Annotation

          def visit(node : ::Crystal::Annotation)
            @entries << node
            true
          end

          def visit(node : ::Crystal::ASTNode)
            true
          end
        end

        private def self.collect_calls(node : ::Crystal::ASTNode) : Array(::Crystal::Call)
          collector = CallCollector.new
          node.accept(collector)
          collector.calls
        end

        private def self.collect_annotations(node : ::Crystal::ASTNode) : Array(::Crystal::Annotation)
          collector = AnnotationCollector.new
          node.accept(collector)
          collector.entries
        end
      end
    end
  end
end
