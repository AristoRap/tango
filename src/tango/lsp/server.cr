require "../compiler"
require "./json_rpc"
require "./position"
require "./document"
require "./workspace"
require "./uri_path"
require "./type_hierarchy"

module Tango
  module Lsp
    # A small stdio LSP server. It exposes text sync, push diagnostics, and
    # goto-definition, reusing the same `Tango.snapshot` data the CLI already
    # produces.
    # Open-buffer changes refresh current syntax immediately and schedule only
    # owning roots through the shared resolver. Crystal's global semantic phase
    # remains process-isolated behind revisioned editor projections.
    class Server
      include TypeHierarchyProjection
      include UriPath
      private alias DiagnosticFixEditToken = NamedTuple(
        path: String,
        startOffset: Int32,
        endOffset: Int32,
        newText: String)
      private alias DiagnosticFixToken = NamedTuple(
        kind: String,
        title: String,
        documentVersion: Int32?,
        analysisRevision: Int64,
        edits: Array(DiagnosticFixEditToken))
      private alias LspTextEdit = NamedTuple(range: Position::LspRange, newText: String)
      private alias LspDiagnostic = NamedTuple(
        range: Position::LspRange,
        severity: Int32,
        code: String,
        source: String,
        message: String,
        tags: Array(Int32),
        data: DiagnosticFixToken?)

      private record ResolvedPosition,
        uri : String,
        document : Document,
        snapshot : Compiler::Snapshot,
        line : Int32,
        column : Int32

      def initialize(@input : IO = STDIN, @output : IO = STDOUT, @log : IO = STDERR)
        @position_encoding = Position::Encoding::UTF16
        @shutdown = false
        @published_diagnostic_uris = Set(String).new
        @workspace = Workspace.new(@log, on_analysis: -> { publish_diagnostics })
      end

      def run : Nil
        while message = JsonRpc.read_message(@input, @log)
          handle(message)
        end
        @workspace.drain
      ensure
        @workspace.stop
      end

      private def handle(message : JSON::Any) : Nil
        method = message["method"]?.try(&.as_s)
        return unless method

        id = message["id"]?
        params = message["params"]? || JSON::Any.new(nil)

        case method
        when "initialize"
          respond(id, initialize_result(params))
        when "initialized"
          nil
        when "shutdown"
          @shutdown = true
          respond(id, nil)
        when "exit"
          exit(@shutdown ? 0 : 1)
        when "textDocument/didOpen"
          doc = params["textDocument"]
          uri = doc["uri"].as_s
          text = doc["text"].as_s
          version = doc["version"]?.try(&.as_i)
          @workspace.open(uri, uri_to_path(uri), text, version)
          publish_diagnostics
        when "textDocument/didChange"
          uri = params["textDocument"]["uri"].as_s
          text = params["contentChanges"].as_a.last["text"].as_s
          version = params["textDocument"]["version"]?.try(&.as_i)
          @workspace.change(uri, uri_to_path(uri), text, version)
          publish_diagnostics
        when "textDocument/didClose"
          uri = params["textDocument"]["uri"].as_s
          @workspace.close(uri)
          publish_diagnostics
        when "textDocument/definition"
          respond(id, definition_result(params))
        when "textDocument/typeDefinition"
          respond(id, type_definition_result(params))
        when "textDocument/inlayHint"
          respond(id, inlay_hint_result(params))
        when "textDocument/semanticTokens/full"
          respond(id, semantic_tokens_result(params))
        when "textDocument/prepareTypeHierarchy"
          respond(id, prepare_type_hierarchy_result(params))
        when "typeHierarchy/supertypes"
          respond(id, type_hierarchy_supertypes_result(params))
        when "typeHierarchy/subtypes"
          respond(id, type_hierarchy_subtypes_result(params))
        when "textDocument/hover"
          respond(id, hover_result(params))
        when "textDocument/documentSymbol"
          respond(id, document_symbol_result(params))
        when "workspace/symbol"
          respond(id, workspace_symbol_result(params))
        when "textDocument/references"
          respond(id, references_result(params))
        when "textDocument/documentHighlight"
          respond(id, document_highlight_result(params))
        when "textDocument/completion"
          respond(id, completion_result(params))
        when "textDocument/signatureHelp"
          respond(id, signature_help_result(params))
        when "textDocument/prepareRename"
          respond(id, prepare_rename_result(params))
        when "textDocument/rename"
          respond(id, rename_result(params))
        when "textDocument/codeAction"
          respond(id, code_action_result(params))
        when "textDocument/formatting"
          respond(id, formatting_result(params))
        else
          respond(id, nil) if id
        end
      rescue ex
        JsonRpc.log(@log, "error handling #{message["method"]?}: #{ex.message}")
        respond(message["id"]?, nil) if message["id"]?
      end

      private def publish_diagnostics : Nil
        grouped = {} of String => Array(NamedTuple(diagnostic: Diagnostic, index: Position::LineIndex))
        seen = Set({String, String, String, Int32, Int32, Int32}).new

        @workspace.root_documents.each do |document|
          document.snapshot.diagnostics.each do |diagnostic|
            path = diagnostic.file || document.path
            file = document.snapshot.source.file?(path)
            next unless file
            key = {path, diagnostic.code, diagnostic.message, diagnostic.line, diagnostic.column, diagnostic.size}
            next unless seen.add?(key)

            uri = @workspace.uri_for_path(path) || path_to_uri(path)
            grouped[uri] ||= [] of NamedTuple(diagnostic: Diagnostic, index: Position::LineIndex)
            grouped[uri] << {diagnostic: diagnostic, index: Position::LineIndex.new(file.code)}
          end
        end

        uris = Set(String).new
        @workspace.documents.each_key { |uri| uris << uri }
        @published_diagnostic_uris.each { |uri| uris << uri }
        grouped.each_key { |uri| uris << uri }
        uris.to_a.sort.each do |uri|
          diagnostics = grouped[uri]?.try do |entries|
            entries.map { |entry| to_lsp_diagnostic(entry[:diagnostic], entry[:index], uri) }
          end || [] of LspDiagnostic
          publish(uri, diagnostics, @workspace.document?(uri).try(&.version))
        end
        @published_diagnostic_uris = grouped.keys.to_set
      end

      private def to_lsp_diagnostic(d : Tango::Diagnostic, index : Position::LineIndex, uri : String) : LspDiagnostic
        {
          range:    index.range(d.line, d.column, d.size, @position_encoding),
          severity: d.severity.warning? ? 2 : 1,
          code:     d.code,
          source:   "tango",
          message:  d.message,
          tags:     d.unnecessary ? [1] : [] of Int32, # 1 = Unnecessary (dimmed)
          data:     diagnostic_fix_token(d.fix, uri),
        }
      end

      private def diagnostic_fix_token(fix : Diagnostic::Fix?, uri : String) : DiagnosticFixToken?
        return unless fix
        document = @workspace.document?(uri)
        return unless document
        edits = fix.edits.map do |edit|
          {
            path:        edit.range.path,
            startOffset: edit.range.start_offset,
            endOffset:   edit.range.end_offset,
            newText:     edit.new_text,
          }
        end
        {
          kind:             fix.kind.to_s,
          title:            fix.title,
          documentVersion:  document.version,
          analysisRevision: document.analysis_revision,
          edits:            edits,
        }
      end

      private def publish(uri : String, diagnostics, version : Int32?) : Nil
        if version
          notify("textDocument/publishDiagnostics", {uri: uri, version: version, diagnostics: diagnostics})
        else
          notify("textDocument/publishDiagnostics", {uri: uri, diagnostics: diagnostics})
        end
      end

      private def definition_result(params : JSON::Any)
        resolved = resolve_position(params)
        return nil unless resolved

        target = Compiler::Editor::Definition.at(resolved.snapshot, resolved.document.path, resolved.line, resolved.column)
        return nil unless target

        target_file = resolved.snapshot.source.files.find { |file| file.path == target.path }
        return nil unless target_file
        semantic_range = target_file.range_at(target.line, target.column, target.size)
        location(semantic_range, resolved.snapshot)
      end

      private def type_definition_result(params : JSON::Any)
        resolved = resolve_position(params)
        return nil unless resolved

        result = Compiler::Editor::TypeDefinition.at(
          resolved.snapshot,
          resolved.document.path,
          resolved.line,
          resolved.column
        )
        result.try { |type_definition| location(type_definition.target, resolved.snapshot) }
      end

      private def inlay_hint_result(params : JSON::Any)
        uri = params["textDocument"]["uri"].as_s
        document = @workspace.document?(uri)
        return [] of JSON::Any unless document
        snapshot = @workspace.analysis_snapshot?(document.path, uri)
        return [] of JSON::Any unless snapshot
        analyzed = snapshot.source.file?(document.path)
        return [] of JSON::Any unless analyzed

        requested = params["range"]
        start_offset = document_offset(document, requested["start"])
        end_offset = document_offset(document, requested["end"])
        result = Compiler::Editor::InlayHints.in(snapshot, document.path, 0, analyzed.code.bytesize)
        result.hints.compact_map do |hint|
          current = @workspace.current_range(hint.anchor, snapshot)
          next unless current && current.start_offset < end_offset && current.end_offset >= start_offset
          range = current_lsp_range(hint.anchor, snapshot)
          next unless range
          {
            position:     hint.kind.type? ? range[:end] : range[:start],
            label:        hint.label,
            kind:         hint.kind.type? ? 1 : 2,
            paddingLeft:  false,
            paddingRight: hint.kind.parameter?,
          }
        end
      end

      private def semantic_tokens_result(params : JSON::Any)
        uri = params["textDocument"]["uri"].as_s
        document = @workspace.document?(uri)
        return {data: [] of Int32} unless document
        snapshot = @workspace.analysis_snapshot?(document.path, uri)
        return {data: [] of Int32} unless snapshot
        analyzed = snapshot.source.file?(document.path)
        return {data: [] of Int32} unless analyzed

        result = Compiler::Editor::SemanticTokens.in(snapshot, document.path, 0, analyzed.code.bytesize)
        previous_line = 0
        previous_start = 0
        data = result.tokens.compact_map do |token|
          range = current_lsp_range(token.range, snapshot)
          next unless range
          start = range[:start]
          finish = range[:end]
          next unless start[:line] == finish[:line]
          delta_line = start[:line] - previous_line
          delta_start = delta_line.zero? ? start[:character] - previous_start : start[:character]
          previous_line = start[:line]
          previous_start = start[:character]
          modifiers = (token.declaration ? 1 : 0) | (token.modification ? 2 : 0)
          [delta_line, delta_start, finish[:character] - start[:character], token.kind.value, modifiers]
        end.flatten
        {data: data}
      end

      private def hover_result(params : JSON::Any)
        resolved = resolve_position(params)
        return nil unless resolved

        hover = Compiler::Editor::Hover.at(resolved.snapshot, resolved.document.path, resolved.line, resolved.column)
        return nil unless hover

        contents = {kind: "markdown", value: Compiler::Editor::HoverMarkdown.render(hover)}
        if range = current_lsp_range(hover.range, resolved.snapshot)
          {
            contents: contents,
            range:    range,
          }
        else
          {contents: contents}
        end
      end

      private def document_symbol_result(params : JSON::Any)
        uri = params["textDocument"]["uri"].as_s
        document = @workspace.document?(uri)
        declarations = document.try do |open_document|
          open_document.snapshot.syntax_surface.declarations_in(open_document.path, outline_only: true)
        end || [] of Frontend::SyntaxSurface::Declaration

        declarations.compact_map do |declaration|
          symbol_information(declaration, document.try(&.snapshot))
        end
      end

      private def workspace_symbol_result(params : JSON::Any)
        query = params["query"]?.try(&.as_s).to_s.downcase
        seen = Set({String, Int32, Int32}).new

        declarations = @workspace.documents.values.flat_map do |document|
          document.snapshot.syntax_surface.declarations.map { |declaration| {declaration: declaration, snapshot: document.snapshot} }
        end
        declarations.compact_map do |entry|
          declaration = entry[:declaration]
          next unless declaration.outline
          next unless query.empty? || declaration.name.downcase.includes?(query)
          key = {declaration.selection_range.path, declaration.selection_range.start_offset, declaration.selection_range.end_offset}
          next unless seen.add?(key)

          symbol_information(declaration, entry[:snapshot])
        end
      end

      private def references_result(params : JSON::Any)
        resolved = resolve_position(params)
        return nil unless resolved

        file = resolved.snapshot.source.file?(resolved.document.path)
        return nil unless file
        offset = file.line_index.byte_offset_at(resolved.line, resolved.column)
        symbol = resolved.snapshot.editor_index.symbol_at(resolved.document.path, offset)
        return nil unless symbol

        include_declaration = params.dig?("context", "includeDeclaration").try(&.as_bool) || false
        locations = resolved.snapshot.editor_index.occurrences(symbol, include_declaration).compact_map do |range|
          location(range, resolved.snapshot)
        end
        locations.empty? ? nil : locations
      end

      private def document_highlight_result(params : JSON::Any)
        resolved = resolve_position(params)
        return nil unless resolved

        file = resolved.snapshot.source.file?(resolved.document.path)
        return nil unless file
        offset = file.line_index.byte_offset_at(resolved.line, resolved.column)
        symbol = resolved.snapshot.editor_index.symbol_at(resolved.document.path, offset)
        return nil unless symbol

        highlights = resolved.snapshot.editor_index.occurrences(symbol).compact_map do |range|
          next unless range.path == resolved.document.path
          lsp_range = current_lsp_range(range, resolved.snapshot)
          lsp_range.try { |current| {range: current, kind: 1} } # Text: read/write is not inferred here.
        end
        highlights.empty? ? nil : highlights
      end

      private def completion_result(params : JSON::Any)
        uri = params["textDocument"]["uri"].as_s
        document = @workspace.document?(uri)
        return nil unless document
        offset = current_offset(params, document)
        context = Compiler::Editor::Context.at(document.text, offset)
        snapshot = @workspace.analysis_snapshot?(document.path, uri)
        receiver = if span = context.receiver
                     snapshot.try { |analysis| @workspace.semantic_receiver(document, span, analysis) }
                   end
        if context.receiver && !receiver
          if recovered = RecoveryQuery.at(@workspace, document, context, context.receiver, offset)
            snapshot = recovered.snapshot
            receiver = recovered.receiver
          end
        end
        surface = query_surface(document, snapshot)
        result = Compiler::Editor::Completion.complete(
          context,
          surface,
          snapshot.try(&.editor_index) || document.snapshot.editor_index,
          receiver,
          document.path,
          offset,
          @workspace.bundled_packages
        )
        replacement = lsp_range(document, context.replacement)
        items = result.items.map do |item|
          {
            label:         item.label,
            kind:          completion_item_kind(item.kind),
            detail:        item.detail,
            documentation: item.documentation.try { |text| {kind: "plaintext", value: text} },
            textEdit:      {range: replacement, newText: item.insert_text || item.label},
          }
        end
        {isIncomplete: result.incomplete, items: items}
      end

      private def signature_help_result(params : JSON::Any)
        uri = params["textDocument"]["uri"].as_s
        document = @workspace.document?(uri)
        return nil unless document
        offset = current_offset(params, document)
        context = Compiler::Editor::Context.at(document.text, offset)
        return nil unless context.call_name
        snapshot = @workspace.analysis_snapshot?(document.path, uri)
        receiver = if span = context.call_receiver
                     snapshot.try { |analysis| @workspace.semantic_receiver(document, span, analysis) }
                   end
        if !snapshot || (context.call_receiver && !receiver)
          if recovered = RecoveryQuery.at(@workspace, document, context, context.call_receiver, offset)
            snapshot = recovered.snapshot
            receiver = recovered.receiver
          end
        end
        return nil unless snapshot
        surface = query_surface(document, snapshot)
        # A member call without an exact compatible receiver has no semantic
        # signature result. Bare calls deliberately have no receiver.
        return nil if context.call_receiver && !receiver
        resolved = context.call_name_span.try do |span|
          @workspace.semantic_symbol(document, span, snapshot)
        end
        result = Compiler::Editor::Completion.signature_help(
          context,
          surface,
          snapshot.editor_index,
          receiver,
          resolved,
          document.path,
          offset
        )
        return nil unless result

        signatures = result.signatures.map do |signature|
          {
            label:         signature.label,
            documentation: signature.documentation.try { |text| {kind: "plaintext", value: text} } || "",
            parameters:    signature.parameters.map do |parameter|
              {label: parameter.label, documentation: parameter.documentation || ""}
            end,
          }
        end
        {
          signatures:      signatures,
          activeSignature: result.active_signature,
          activeParameter: result.active_parameter,
        }
      end

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

      private def query_surface(
        document : Document,
        snapshot : Compiler::Snapshot?,
      ) : Frontend::SyntaxSurface::Index
        current = document.snapshot.syntax_surface
        if current.declarations.empty? && current.scopes.empty?
          snapshot.try(&.syntax_surface) || current
        else
          current
        end
      end

      private def current_offset(params : JSON::Any, document : Document) : Int32
        document_offset(document, params["position"])
      end

      private def document_offset(document : Document, position : JSON::Any) : Int32
        line = position["line"].as_i
        column = document.line_index.tango_column(line, position["character"].as_i, @position_encoding)
        document.source_line_index.byte_offset_at(line + 1, column)
      end

      private def lsp_range(
        document : Document,
        span : Compiler::Editor::Context::Span,
      ) : Position::LspRange
        line, column = document.source_line_index.byte_line_col(span.start_offset)
        document.line_index.range(line, column, span.end_offset - span.start_offset, @position_encoding)
      end

      private def completion_item_kind(kind : Compiler::Editor::Completion::ItemKind) : Int32
        case kind
        in .class?             then 7  # Class
        in .enum?              then 13 # Enum
        in .enum_member?       then 20 # Enum member
        in .module?, .package? then 9  # Module/package
        in .function?          then 3  # Function
        in .method?            then 2  # Method
        in .field?             then 5  # Field
        in .variable?          then 6  # Variable
        end
      end

      private def symbol_information(
        declaration : Frontend::SyntaxSurface::Declaration,
        snapshot : Compiler::Snapshot?,
      )
        range = current_lsp_range(declaration.selection_range, snapshot)
        return nil unless range

        location = {
          uri:   @workspace.uri_for_path(declaration.selection_range.path) || path_to_uri(declaration.selection_range.path),
          range: range,
        }
        if container = declaration.container
          {name: declaration.name, kind: symbol_kind(declaration.kind), location: location, containerName: container}
        else
          {name: declaration.name, kind: symbol_kind(declaration.kind), location: location}
        end
      end

      private def symbol_kind(kind : Frontend::SyntaxSurface::DeclarationKind) : Int32
        case kind
        in .class?       then 5  # Class
        in .enum?        then 10 # Enum
        in .enum_member? then 22 # Enum member
        in .module?      then 11 # Interface
        in .method?      then 6  # Method
        in .field?       then 8  # Field
        in .function?    then 12 # Function
        in .local?       then 13 # Variable
        in .parameter?   then 13 # Variable
        end
      end

      private def formatting_result(params : JSON::Any) : Array(NamedTuple(range: Position::LspRange, newText: String))?
        uri = params["textDocument"]["uri"].as_s
        document = @workspace.document?(uri)
        return nil unless document

        result = Frontend::Crystal::Formatting.format(document.text, document.path)
        return nil unless result.ok?

        formatted = result.formatted_source
        return nil unless formatted
        return [] of NamedTuple(range: Position::LspRange, newText: String) if formatted == document.text

        [{range: document.line_index.full_range(@position_encoding), newText: formatted}]
      end

      private def resolve_position(params : JSON::Any) : ResolvedPosition?
        uri = params["textDocument"]["uri"].as_s
        document = @workspace.document?(uri)
        return nil unless document

        position = params["position"]
        lsp_line = position["line"].as_i
        lsp_character = position["character"].as_i

        column = document.line_index.tango_column(lsp_line, lsp_character, @position_encoding)
        snapshot = @workspace.analysis_snapshot(document.path, uri)
        current_offset = document.source_line_index.byte_offset_at(lsp_line + 1, column)
        semantic_offset = @workspace.semantic_offset(document.path, current_offset, snapshot)
        return nil unless semantic_offset
        semantic_file = snapshot.source.file?(document.path)
        return nil unless semantic_file
        line, semantic_column = semantic_file.line_index.byte_line_col(semantic_offset)
        occurrence_range = snapshot.editor_index.reference_at(document.path, semantic_offset).try(&.range) ||
                           snapshot.editor_index.declaration_at(document.path, semantic_offset).try(&.range)
        return nil if occurrence_range && !@workspace.current_range(occurrence_range, snapshot)
        ResolvedPosition.new(uri, document, snapshot, line, semantic_column)
      end

      private def initialize_result(params : JSON::Any)
        @position_encoding = negotiate_encoding(params)
        @workspace.configure_roots(workspace_roots(params))
        {
          capabilities: {
            textDocumentSync:       1,
            definitionProvider:     true,
            typeDefinitionProvider: true,
            inlayHintProvider:      true,
            semanticTokensProvider: {
              legend: {tokenTypes: %w(class function method variable parameter property), tokenModifiers: %w(declaration modification)},
              full:   true,
            },
            typeHierarchyProvider:     true,
            hoverProvider:             true,
            documentSymbolProvider:    true,
            workspaceSymbolProvider:   true,
            referencesProvider:        true,
            documentHighlightProvider: true,
            completionProvider:        {
              resolveProvider:   false,
              triggerCharacters: [".", "\"", "/"],
            },
            signatureHelpProvider: {
              triggerCharacters:   ["(", ","],
              retriggerCharacters: [","],
            },
            renameProvider:             {prepareProvider: true},
            codeActionProvider:         {codeActionKinds: ["quickfix"], resolveProvider: false},
            documentFormattingProvider: true,
            positionEncoding:           Position.encoding_name(@position_encoding),
          },
          serverInfo: {name: "tango"},
        }
      end

      private def negotiate_encoding(params : JSON::Any) : Position::Encoding
        supported = params.dig?("capabilities", "general", "positionEncodings")
        encodings = supported.try(&.as_a?)
        return Position::Encoding::UTF16 unless encodings

        if encodings.any? { |encoding| encoding.as_s? == "utf-8" }
          Position::Encoding::UTF8
        elsif encodings.any? { |encoding| encoding.as_s? == "utf-32" }
          Position::Encoding::UTF32
        else
          Position::Encoding::UTF16
        end
      end

      private def workspace_roots(params : JSON::Any) : Array(String)
        if folders = params["workspaceFolders"]?.try(&.as_a?)
          return folders.compact_map do |folder|
            folder["uri"]?.try(&.as_s?).try { |uri| uri_to_path(uri) }
          end
        end
        if root_uri = params["rootUri"]?.try(&.as_s?)
          return [uri_to_path(root_uri)]
        end
        if root_path = params["rootPath"]?.try(&.as_s?)
          return [root_path]
        end
        [] of String
      end

      private def respond(id : JSON::Any?, result) : Nil
        return unless id
        JsonRpc.write_message(@output, {jsonrpc: "2.0", id: id, result: result})
      end

      private def notify(method : String, params) : Nil
        JsonRpc.write_message(@output, {jsonrpc: "2.0", method: method, params: params})
      end

      private def location(range : Source::Range, snapshot : Compiler::Snapshot)
        lsp_range = current_lsp_range(range, snapshot)
        return nil unless lsp_range

        {
          uri:   @workspace.uri_for_path(range.path) || path_to_uri(range.path),
          range: lsp_range,
        }
      end

      private def current_lsp_range(range : Source::Range, snapshot : Compiler::Snapshot?) : Position::LspRange?
        current = snapshot ? @workspace.current_range(range, snapshot) : range
        return nil unless current
        source = snapshot ? @workspace.current_source(current.path, snapshot) : @workspace.current_source?(current.path)
        source ||= snapshot.try { |analysis| analysis.source.file?(current.path).try(&.code) }
        return nil unless source

        line, column = Source::LineIndex.new(source).byte_line_col(current.start_offset)
        Position::LineIndex.new(source).range(line, column, current.length, @position_encoding)
      end
    end
  end
end
