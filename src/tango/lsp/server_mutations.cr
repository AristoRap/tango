module Tango
  module Lsp
    # Workspace mutations share stricter freshness and editable-path rules than
    # read-only requests. Server owns protocol dispatch; this reopening owns the
    # rename/code-action plans and their versioned workspace edits.
    class Server
      private def prepare_rename_result(params : JSON::Any)
        resolved = resolve_position(params)
        return nil unless resolved
        offset = semantic_offset(resolved)
        return nil unless offset
        preparation = Compiler::Editor::Rename.prepare(
          resolved.snapshot,
          resolved.document.path,
          offset
        )
        return nil unless preparation
        ranges = Compiler::Editor::Rename.ranges(resolved.snapshot.editor_index, preparation.family)
        return nil unless mutation_ranges_available?(resolved.snapshot, ranges)
        range = current_lsp_range(preparation.range, resolved.snapshot)
        range.try { |value| {range: value, placeholder: preparation.placeholder} }
      end

      private def rename_result(params : JSON::Any)
        resolved = resolve_position(params)
        return nil unless resolved
        offset = semantic_offset(resolved)
        return nil unless offset
        plan = Compiler::Editor::Rename.plan(
          resolved.snapshot,
          resolved.document.path,
          offset,
          params["newName"].as_s
        )
        return nil unless plan
        ranges = plan.edits.map(&.range)
        return nil unless mutation_ranges_available?(resolved.snapshot, ranges)
        workspace_edit(plan.edits, resolved.snapshot)
      end

      private def code_action_result(params : JSON::Any)
        uri = params["textDocument"]["uri"].as_s
        document = @workspace.document?(uri)
        return [] of Nil unless document
        snapshot = @workspace.analysis_snapshot?(document.path, uri)
        return [] of Nil unless snapshot

        diagnostics = params.dig?("context", "diagnostics").try(&.as_a?) || [] of JSON::Any
        diagnostics.compact_map do |reported|
          data = reported["data"]?
          next unless data
          next unless diagnostic_token_current?(data, document)
          code = reported["code"]?.try(&.as_s)
          next unless code
          diagnostic = snapshot.diagnostics.find do |candidate|
            candidate.code == code && candidate.fix.try do |fix|
              diagnostic_fix_matches?(fix, data)
            end
          end
          next unless diagnostic && (fix = diagnostic.fix)
          ranges = fix.edits.map(&.range)
          next unless mutation_ranges_available?(snapshot, ranges)
          edit = workspace_edit(fix.edits, snapshot)
          next unless edit
          {
            title:       fix.title,
            kind:        "quickfix",
            diagnostics: [reported],
            isPreferred: true,
            edit:        edit,
          }
        end
      end

      private def diagnostic_token_current?(data : JSON::Any, document : Document) : Bool
        version = data["documentVersion"]?
        revision = data["analysisRevision"]?
        return false unless version && revision
        version.as_i?.try(&.to_i32) == document.version &&
          revision.as_i64? == document.analysis_revision
      end

      private def diagnostic_fix_matches?(fix : Diagnostic::Fix, data : JSON::Any) : Bool
        return false unless data["kind"]?.try(&.as_s) == fix.kind.to_s
        return false unless data["title"]?.try(&.as_s) == fix.title
        reported = data["edits"]?.try(&.as_a?)
        return false unless reported && reported.size == fix.edits.size
        fix.edits.zip(reported).all? do |edit, token|
          token["path"]?.try(&.as_s) == edit.range.path &&
            token["startOffset"]?.try(&.as_i) == edit.range.start_offset &&
            token["endOffset"]?.try(&.as_i) == edit.range.end_offset &&
            token["newText"]?.try(&.as_s) == edit.new_text
        end
      end

      private def mutation_ranges_available?(snapshot : Compiler::Snapshot, ranges : Array(Source::Range)) : Bool
        paths = ranges.map(&.path).uniq
        !ranges.empty? &&
          paths.all? { |path| @workspace.editable_path?(path) } &&
          @workspace.snapshot_current?(snapshot, paths)
      end

      private def semantic_offset(resolved : ResolvedPosition) : Int32?
        resolved.snapshot.source.file?(resolved.document.path).try do |file|
          file.line_index.byte_offset_at(resolved.line, resolved.column)
        end
      end

      private def workspace_edit(edits : Array(T), snapshot : Compiler::Snapshot) forall T
        grouped = Hash(String, Array(LspTextEdit)).new { |hash, path| hash[path] = [] of LspTextEdit }
        edits.each do |edit|
          range = current_lsp_range(edit.range, snapshot)
          return nil unless range
          grouped[edit.range.path] << {range: range, newText: edit.new_text}
        end
        changes = grouped.keys.sort.map do |path|
          {
            textDocument: {
              uri:     @workspace.uri_for_path(path) || path_to_uri(path),
              version: @workspace.version_for_path(path),
            },
            edits: grouped[path],
          }
        end
        {documentChanges: changes}
      end
    end
  end
end
