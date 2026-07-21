module Tango
  module Lsp
    private class AnalysisState
      getter requests = [] of AnalysisRequest
      getter root_generations = Hash(String, Int64).new(0_i64)
      getter worker : AnalysisWorker

      def initialize(@worker : AnalysisWorker)
      end
    end

    # Open buffers are compiler inputs, not a second path resolver. Current
    # syntax is refreshed immediately; only roots whose source graph owns a
    # changed path are submitted to revisioned background analysis.
    class Workspace
      private record AnalysisContext, path : String

      private class WorkspaceState
        getter documents = {} of String => Document
        getter analysis_contexts = {} of String => AnalysisContext
        property roots = [] of String
      end

      getter bundled_packages : Array(String)
      getter revision : Int64 = 0_i64

      def initialize(
        @log : IO = STDERR,
        debounce : Time::Span = AnalysisWorker::DEFAULT_DEBOUNCE,
        recovery_limit : Time::Span = AnalysisWorker::DEFAULT_RECOVERY_LIMIT,
        @on_analysis : Proc(Nil) = -> { nil },
      )
        root = Tango::Workspace::Layout.bundled_packages_dir
        @bundled_packages = Dir.glob(File.join(root, "**", "*.tn")).sort.map do |path|
          path.sub("#{root}#{File::SEPARATOR}", "").rchop(".tn")
        end.select { |request| Frontend::SourceGraph.bundled_request?(request) }
        worker = AnalysisWorker.new(@log, debounce, recovery_limit) do |result|
          apply_analysis(result)
        end
        @analysis = AnalysisState.new(worker)
        @state = WorkspaceState.new
      end

      def documents : Hash(String, Document)
        @state.documents
      end

      def analysis_requests : Array(AnalysisRequest)
        @analysis.requests
      end

      def worker : AnalysisWorker
        @analysis.worker
      end

      def configure_roots(paths : Enumerable(String)) : Nil
        @state.roots = paths.compact_map do |path|
          expanded = File.expand_path(path)
          expanded if File.directory?(expanded)
        end.uniq
      end

      def open(uri : String, path : String, text : String, version : Int32?) : Document
        advance_revision
        affected = documents_owning(path)
        overlays = overlay_texts
        overlays[path] = text
        resolver = Frontend::SourceGraph.resolver(overlays)
        @state.documents.each_value do |existing|
          next unless resolves_open_path?(existing, path, resolver)
          affected << existing unless affected.includes?(existing)
        end

        context = owning_disk_context(path, resolver) if affected.empty?
        document = Document.new(
          uri,
          path,
          text,
          version,
          resolver,
          @revision
        )
        @state.documents[uri] = document
        @state.analysis_contexts[uri] = context if context
        affected << document unless affected.includes?(document)
        affected.each { |existing| existing.refresh_surface(resolver, @revision) }
        schedule_affected(affected)
        document
      end

      def change(uri : String, path : String, text : String, version : Int32?) : Document
        advance_revision
        affected = documents_owning(path)
        overlays = overlay_texts
        overlays[path] = text
        resolver = Frontend::SourceGraph.resolver(overlays)

        if document = @state.documents[uri]?
          document.update(text, version, resolver, @revision)
        else
          document = Document.new(uri, path, text, version, resolver, @revision)
          @state.documents[uri] = document
        end
        affected << document unless affected.includes?(document)
        affected.each do |other|
          other.refresh_surface(resolver, @revision) unless other.uri == uri
        end
        schedule_affected(affected)
        document
      end

      def close(uri : String) : Document?
        removed_document = @state.documents[uri]?
        return unless removed_document
        affected = documents_owning(removed_document.path).reject(&.uri.==(uri))
        removed = @state.documents.delete(uri)
        @state.analysis_contexts.delete(uri)
        advance_revision
        resolver = Frontend::SourceGraph.resolver(overlay_texts)
        affected.each { |document| document.refresh_surface(resolver, @revision) }
        schedule_affected(affected)
        removed
      end

      def recover_snapshot(path : String, uri : String, repaired_text : String) : AnalysisResult?
        document = @state.documents[uri]?
        return unless document
        overlays = overlay_texts
        overlays[path] = repaired_text
        request = analysis_request(document, shadow: true, text: repaired_text, overlays: overlays)
        worker.recover(request)
      end

      # Parser-only catalog recovery for an invalid current buffer. Closing the
      # cursor shape lets SyntaxSurfaceBuilder retain declarations; no semantic
      # fact from this snapshot is trusted until the isolated worker proves the
      # typed repair below.
      def recovery_surface(path : String, uri : String, repaired_text : String) : Frontend::SyntaxSurface::Index?
        return unless @state.documents[uri]?
        overlays = overlay_texts
        overlays[path] = repaired_text
        resolver = Frontend::SourceGraph.resolver(overlays)
        Tango.editor_surface_snapshot(repaired_text, filename: path, resolver: resolver).syntax_surface
      end

      def drain : Nil
        worker.drain
      end

      def stop : Nil
        worker.stop
      end

      def document?(uri : String) : Document?
        @state.documents[uri]?
      end

      def document_for_path?(path : String) : Document?
        document_for_path(path)
      end

      def editable_path?(path : String) : Bool
        return false if Tango::Workspace::Layout.bundled_package_path?(path)
        prelude = File.expand_path(Tango::Workspace::Layout.prelude_dir)
        expanded = File.expand_path(path)
        return false if expanded == prelude || expanded.starts_with?("#{prelude}#{File::SEPARATOR}")
        return true if document_for_path(path)
        File.file?(path) && File::Info.writable?(path)
      end

      # Mutating editor operations require the exact analyzed text for every
      # touched source. Last-good compatibility is sufficient for read-only
      # navigation, but never for workspace edits.
      def snapshot_current?(snapshot : Compiler::Snapshot, paths : Enumerable(String)) : Bool
        paths.uniq.all? do |path|
          analyzed = snapshot.source.file?(path)
          next false unless analyzed
          if document = document_for_path(path)
            document.text == analyzed.code
          else
            File.file?(path) && File.read(path) == analyzed.code
          end
        rescue
          false
        end
      end

      def version_for_path(path : String) : Int32?
        document_for_path(path).try(&.version)
      end

      # An open dependency is a buffer overlay, not a second program root. A
      # document is owned when another open source graph contains its path.
      # Mutual cycle membership is broken by stable URI order, never graph size.
      def root_documents : Array(Document)
        @state.documents.values.reject do |candidate|
          @state.documents.each_value.any? do |owner|
            document_owns?(owner, candidate, semantic: false)
          end
        end
      end

      def analysis_snapshot?(path : String, preferred_uri : String) : Compiler::Snapshot?
        snapshot = compatible_analysis_snapshot(path, preferred_uri)
        return snapshot if snapshot
        initial_requests = @analysis.requests.count { |request| request.root_uri == preferred_uri }
        return nil unless initial_requests == 1

        # Initial open schedules analysis before the document becomes queryable.
        # A semantic request may await that already-running isolated worker, but
        # it never starts a compiler walk or builds facts on the request fiber.
        worker.drain
        compatible_analysis_snapshot(path, preferred_uri)
      end

      private def compatible_analysis_snapshot(path : String, preferred_uri : String) : Compiler::Snapshot?
        preferred = @state.documents[preferred_uri]?
        roots = semantic_root_documents
        if preferred && roots.includes?(preferred)
          snapshot = preferred.semantic_snapshot
          return snapshot if snapshot && usable_for_query?(snapshot, path)
        end

        owner = roots
          .select { |document| usable_for_query?(document.semantic_snapshot, path) }
          .min_by? { |document| Source::File.canonical_identity(document.path) }
        if owner && (snapshot = owner.semantic_snapshot)
          return snapshot
        end
        if preferred && (snapshot = preferred.semantic_snapshot)
          return snapshot
        end
        nil
      end

      def semantic_receiver(
        document : Document,
        span : Compiler::Editor::Context::Span,
        snapshot : Compiler::Snapshot,
      ) : Compiler::Editor::Index::Receiver?
        offsets = compatible_semantic_span(document, span, snapshot)
        return unless offsets
        start_offset, end_offset = offsets
        return unless end_offset > start_offset

        # Most expressions cover the full lexical receiver, so its final byte
        # selects the outermost semantic value. Crystal's fallback node for a
        # standalone constant currently has a one-byte span; only when the
        # normal probe misses may the exact compatible receiver start recover it.
        snapshot.editor_index.receiver_at(document.path, end_offset - 1) ||
          snapshot.editor_index.receiver_at(document.path, start_offset)
      end

      def semantic_symbol(
        document : Document,
        span : Compiler::Editor::Context::Span,
        snapshot : Compiler::Snapshot,
      ) : Compiler::Editor::Index::SymbolId?
        offsets = compatible_semantic_span(document, span, snapshot)
        return unless offsets
        start_offset, end_offset = offsets
        return unless end_offset > start_offset

        snapshot.editor_index.symbol_at(document.path, end_offset - 1)
      end

      def semantic_offset(path : String, current_offset : Int32, snapshot : Compiler::Snapshot) : Int32?
        if document = document_for_path(path)
          document.semantic_offset(snapshot, current_offset)
        else
          current_offset
        end
      end

      def current_range(range : Source::Range, snapshot : Compiler::Snapshot) : Source::Range?
        if document = document_for_path(range.path)
          document.current_range(snapshot, range)
        else
          range
        end
      end

      def current_source(path : String, snapshot : Compiler::Snapshot) : String?
        document_for_path(path).try(&.text) || snapshot.source.file?(path).try(&.code)
      end

      def current_source?(path : String) : String?
        document_for_path(path).try(&.text)
      end

      def uri_for_path(path : String) : String?
        @state.documents.each_value.find { |document| document.path == path }.try(&.uri)
      end

      private def advance_revision : Nil
        @revision += 1
      end

      private def documents_owning(path : String) : Array(Document)
        @state.documents.values.select do |document|
          document.path == path ||
            document.snapshot.source.file?(path) ||
            document.semantic_snapshot.try(&.source.file?(path))
        end
      end

      private def resolves_open_path?(
        document : Document,
        path : String,
        resolver : Frontend::SourceGraph::Resolver,
      ) : Bool
        document.snapshot.source.requires.any? do |directive|
          from = document.snapshot.source.file?(directive.from)
          from && resolver.call(directive.request, from).any? { |file| file.path == path }
        end
      end

      private def schedule_affected(affected : Array(Document)) : Nil
        roots = root_documents
        scheduled = Set(String).new
        affected.each do |document|
          owners = if roots.includes?(document)
                     [document]
                   else
                     roots.select { |candidate| candidate.snapshot.source.file?(document.path) }
                   end
          owners.each do |root|
            next unless scheduled.add?(root.uri)
            schedule(root)
          end
        end
      end

      private def schedule(root : Document) : Nil
        @analysis.root_generations[root.uri] += 1
        context = @state.analysis_contexts[root.uri]?
        request = if context
                    analysis_request(
                      root,
                      text: analysis_text_for(context.path),
                      root_path: context.path
                    )
                  else
                    analysis_request(root)
                  end
        @analysis.requests << request
        worker.schedule(request)
      end

      private def analysis_request(
        root : Document,
        shadow : Bool = false,
        text : String = root.text,
        overlays : Hash(String, String) = overlay_texts,
        root_path : String = root.path,
      ) : AnalysisRequest
        versions = {} of String => Int32?
        source = root.semantic_snapshot || root.snapshot
        source.source.files.each do |file|
          if document = document_for_path(file.path)
            versions[file.path] = document.version
          end
        end
        versions[root.path] = root.version
        AnalysisRequest.new(
          @revision,
          @analysis.root_generations[root.uri],
          root.uri,
          root_path,
          text,
          overlays,
          versions,
          shadow
        )
      end

      private def apply_analysis(result : AnalysisResult) : Nil
        request = result.request
        return if request.shadow
        return unless @analysis.root_generations[request.root_uri] == request.root_generation
        return unless versions_current?(request.versions)
        document = @state.documents[request.root_uri]?
        return unless document

        document.apply_analysis(result.snapshot, request.revision)
        @on_analysis.call
      end

      private def versions_current?(versions : Hash(String, Int32?)) : Bool
        versions.all? do |path, version|
          document_for_path(path).try(&.version) == version
        end
      end

      private def overlay_texts : Hash(String, String)
        @state.documents.values.to_h { |document| {document.path, document.text} }
      end

      # A required file may not instantiate any of its declarations when it is
      # compiled as an entrypoint. Find the largest disk graph in the announced
      # workspace that owns it, using the same resolver (including glob and
      # open-buffer overlays) as normal compilation.
      private def owning_disk_context(
        path : String,
        resolver : Frontend::SourceGraph::Resolver,
      ) : AnalysisContext?
        target_identity = canonical_path(path)
        best_context : AnalysisContext? = nil
        best_score = 0

        roots_containing(path).each do |root|
          Dir.glob(File.join(root, "**", "*.tn")).sort.each do |candidate_path|
            next if canonical_path(candidate_path) == target_identity
            source = File.read(candidate_path)
            next unless source.includes?("require")

            entrypoint = Source::File.new(candidate_path, source, canonical_path(candidate_path))
            loaded = Frontend::SourceGraph::Loader.load(entrypoint, resolver)
            next unless loaded.diagnostics.empty?
            next unless loaded.source.files.any? { |file| canonical_path(file.path) == target_identity }

            score = loaded.source.files.size
            if best_context.nil? || score > best_score
              best_context = AnalysisContext.new(candidate_path)
              best_score = score
            end
          rescue ex : File::Error
            @log.puts "tango lsp root discovery skipped #{candidate_path}: #{ex.message}"
            next
          end
        end
        best_context
      end

      private def roots_containing(path : String) : Array(String)
        expanded = File.expand_path(path)
        @state.roots.select do |root|
          expanded == root || expanded.starts_with?("#{root}#{File::SEPARATOR}")
        end
      end

      private def analysis_text_for(path : String) : String
        document_for_path(path).try(&.text) || File.read(path)
      end

      private def canonical_path(path : String) : String
        Source::File.canonical_identity(path)
      end

      private def compatible_semantic_span(
        document : Document,
        span : Compiler::Editor::Context::Span,
        snapshot : Compiler::Snapshot,
      ) : {Int32, Int32}?
        semantic_file = snapshot.source.file?(document.path)
        return unless semantic_file
        start_offset = document.semantic_offset(snapshot, span.start_offset)
        end_offset = document.semantic_offset(snapshot, span.end_offset)
        return unless start_offset && end_offset

        current_text = document.text.byte_slice(span.start_offset, span.end_offset - span.start_offset)
        semantic_text = semantic_file.code.byte_slice(start_offset, end_offset - start_offset)
        return unless current_text == semantic_text

        {start_offset, end_offset}
      end

      private def document_for_path(path : String) : Document?
        @state.documents.each_value.find { |document| document.path == path }
      end

      private def semantic_root_documents : Array(Document)
        @state.documents.values.reject do |candidate|
          candidate_snapshot = candidate.semantic_snapshot
          next true unless candidate_snapshot

          @state.documents.each_value.any? do |owner|
            document_owns?(owner, candidate, semantic: true)
          end
        end
      end

      private def document_owns?(owner : Document, candidate : Document, semantic : Bool) : Bool
        return false if owner.uri == candidate.uri
        owner_source = semantic ? owner.semantic_snapshot.try(&.source) : owner.snapshot.source
        return false unless owner_source && owner_source.file?(candidate.path)

        candidate_source = semantic ? candidate.semantic_snapshot.try(&.source) : candidate.snapshot.source
        mutual = candidate_source.try(&.file?(owner.path))
        !mutual || owner.uri < candidate.uri
      end

      private def usable_for_query?(snapshot : Compiler::Snapshot?, path : String) : Bool
        snapshot && snapshot.semantic_ready? && snapshot.source.file?(path) ? true : false
      end
    end
  end
end
