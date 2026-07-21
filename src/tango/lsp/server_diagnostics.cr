module Tango
  module Lsp
    class Server
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
        message = ([d.message] + d.hints.map { |hint| "help: #{hint}" }).join("\n")
        {
          range:              diagnostic_range(d, index),
          severity:           d.severity.warning? ? 2 : 1,
          code:               d.code,
          source:             "tango",
          message:            message,
          tags:               d.unnecessary ? [1] : [] of Int32,
          relatedInformation: d.related.map { |range, note| related_diagnostic(range, note) },
          data:               diagnostic_fix_token(d.fix, uri),
        }
      end

      private def diagnostic_range(diagnostic : Diagnostic, index : Position::LineIndex) : Position::LspRange
        if range = diagnostic.range
          index.range(range.line, range.column, range.length, @position_encoding)
        else
          index.range(diagnostic.line, diagnostic.column, diagnostic.size, @position_encoding)
        end
      end

      private def related_diagnostic(range : Source::Range, message : String) : LspRelatedDiagnostic
        source = @workspace.root_documents.compact_map { |document| document.snapshot.source.file?(range.path).try(&.code) }.first? || ""
        index = Position::LineIndex.new(source)
        {
          location: {
            uri:   @workspace.uri_for_path(range.path) || path_to_uri(range.path),
            range: index.range(range.line, range.column, range.length, @position_encoding),
          },
          message: message,
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
    end
  end
end
