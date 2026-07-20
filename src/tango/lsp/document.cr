module Tango
  module Lsp
    # Versioned state for one open document. A change refreshes current syntax
    # and line indices immediately; compatible successful semantic snapshots
    # arrive later and remain immutable query inputs.
    class Document
      getter uri : String
      getter path : String
      getter text : String
      getter version : Int32?
      getter line_index : Position::LineIndex
      getter source_line_index : Source::LineIndex
      getter snapshot : Compiler::Snapshot
      getter semantic_snapshot : Compiler::Snapshot?
      getter graph_revision : Int64
      getter analysis_revision : Int64

      def initialize(
        @uri : String,
        @path : String,
        text : String,
        version : Int32? = nil,
        resolver : Frontend::SourceGraph::Resolver = Frontend::SourceGraph::DISK_RESOLVER,
        @graph_revision : Int64 = 0_i64,
        analysis_path : String? = nil,
        analysis_text : String = text,
      )
        @text = text
        @version = version
        @line_index = Position::LineIndex.new(text)
        @source_line_index = Source::LineIndex.new(text)
        @snapshot = Tango.pre_target_snapshot(analysis_text, filename: analysis_path || path, resolver: resolver)
        @semantic_snapshot = @snapshot.semantic_ready? ? @snapshot : nil
        @analysis_revision = @semantic_snapshot ? @graph_revision : 0_i64
      end

      def update(
        text : String,
        version : Int32? = nil,
        resolver : Frontend::SourceGraph::Resolver = Frontend::SourceGraph::DISK_RESOLVER,
        graph_revision : Int64 = @graph_revision,
      ) : Nil
        @text = text
        @version = version
        @line_index = Position::LineIndex.new(text)
        @source_line_index = Source::LineIndex.new(text)
        @graph_revision = graph_revision
        refresh_surface(resolver)
      end

      def refresh_surface(resolver : Frontend::SourceGraph::Resolver, graph_revision : Int64 = @graph_revision) : Nil
        @graph_revision = graph_revision
        @snapshot = Tango.editor_surface_snapshot(@text, filename: @path, resolver: resolver)
      end

      def apply_analysis(snapshot : Compiler::Snapshot, revision : Int64) : Nil
        @snapshot = snapshot
        @analysis_revision = revision
        @semantic_snapshot = snapshot if snapshot.semantic_ready?
      end

      def semantic_offset(snapshot : Compiler::Snapshot, current_offset : Int32) : Int32?
        semantic_file = snapshot.source.file?(@path)
        return nil unless semantic_file

        map_offset(@text, semantic_file.code, current_offset)
      end

      def current_range(snapshot : Compiler::Snapshot, range : Source::Range) : Source::Range?
        semantic_file = snapshot.source.file?(range.path)
        return nil unless semantic_file

        start_offset = map_offset(semantic_file.code, @text, range.start_offset)
        end_offset = map_offset(semantic_file.code, @text, range.end_offset)
        return nil unless start_offset && end_offset
        semantic_text = semantic_file.code.byte_slice(range.start_offset, range.length)
        current_text = @text.byte_slice(start_offset, end_offset - start_offset)
        return nil unless semantic_text == current_text

        line, column = @source_line_index.byte_line_col(start_offset)
        Source::Range.new(@path, start_offset, end_offset, line, column)
      end

      # Full-buffer sync does not expose edit deltas. A last-good position is
      # compatible only when it lies in the unchanged prefix or suffix shared
      # by both texts. Anything inside the changed middle deliberately fails.
      private def map_offset(from : String, to : String, offset : Int32) : Int32?
        return nil unless offset.in?(0..from.bytesize)
        return offset if from == to

        prefix = common_prefix_size(from, to)
        return offset if offset <= prefix

        suffix = common_suffix_size(from, to, prefix)
        return nil unless offset >= from.bytesize - suffix

        to.bytesize - (from.bytesize - offset)
      end

      private def common_prefix_size(left : String, right : String) : Int32
        limit = Math.min(left.bytesize, right.bytesize)
        index = 0
        while index < limit && left.byte_at(index) == right.byte_at(index)
          index += 1
        end
        index
      end

      private def common_suffix_size(left : String, right : String, prefix : Int32) : Int32
        limit = Math.min(left.bytesize, right.bytesize) - prefix
        size = 0
        while size < limit && left.byte_at(left.bytesize - size - 1) == right.byte_at(right.bytesize - size - 1)
          size += 1
        end
        size
      end
    end
  end
end
