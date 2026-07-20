module Tango
  module Lsp
    # A fact-only cursor repair. Repaired source is compiled in an isolated
    # shadow process and is never installed into Workspace state or used for
    # diagnostic publication.
    module RecoveryQuery
      record Result,
        snapshot : Compiler::Snapshot,
        receiver : Compiler::Editor::Index::Receiver?,
        elapsed : Time::Span,
        shadow : Bool = true

      def self.at(
        workspace : Workspace,
        document : Document,
        context : Compiler::Editor::Context,
        receiver_span : Compiler::Editor::Context::Span?,
        offset : Int32,
      ) : Result?
        surface = document.snapshot.syntax_surface
        if surface.declarations.empty? && context.call_name
          parseable = call_repair(document.text, context, offset, %Q(""))
          surface = workspace.recovery_surface(document.path, document.uri, parseable) || surface
        end

        repairs(document.text, context, offset, surface).each do |repaired|
          analysis = workspace.recover_snapshot(document.path, document.uri, repaired)
          next unless analysis && analysis.snapshot.semantic_ready?

          receiver = receiver_span.try do |span|
            semantic_receiver(analysis.snapshot, document.path, span)
          end
          return Result.new(analysis.snapshot, receiver, analysis.elapsed)
        end
        nil
      end

      # A typed call repair is only a candidate generator. The isolated compiler
      # must resolve it before any fact is returned. An appended recursive helper
      # gives the hole its declared source type while preserving every original
      # offset before the cursor; it is never installed or emitted.
      private def self.repairs(
        text : String,
        context : Compiler::Editor::Context,
        offset : Int32,
        surface : Frontend::SyntaxSurface::Index,
      ) : Array(String)
        if context.completion_kind.member? && offset > 0 && text.byte_at(offset - 1) == '.'.ord.to_u8
          return [text.byte_slice(0, offset - 1) + text.byte_slice(offset, text.bytesize - offset)]
        end

        return [] of String unless context.call_name
        typed = candidate_parameter_types(text, context, surface).first(3).map_with_index do |type, index|
          typed_call_repair(text, context, offset, type, index)
        end
        return typed unless typed.empty?

        [call_repair(text, context, offset, %Q(""))]
      end

      private def self.candidate_parameter_types(
        text : String,
        context : Compiler::Editor::Context,
        surface : Frontend::SyntaxSurface::Index,
      ) : Array(String)
        name = context.call_name
        return [] of String unless name
        receiver = context.call_receiver.try do |span|
          text.byte_slice(span.start_offset, span.end_offset - span.start_offset)
        end

        surface.declarations.compact_map do |declaration|
          kind = declaration.callable_kind
          next unless kind
          if receiver
            next unless declaration.container == receiver
            if name == "new"
              next unless kind.initializer?
            else
              next unless kind.class_method? && declaration.name == name
            end
          else
            next unless kind.function? && declaration.name == name
          end
          declaration.parameters[context.active_parameter]?.try(&.explicit_type)
        end.uniq
      end

      private def self.typed_call_repair(
        text : String,
        context : Compiler::Editor::Context,
        offset : Int32,
        type : String,
        index : Int32,
      ) : String
        helper = "__tango_editor_recovery_#{offset}_#{index}"
        repaired = call_repair(text, context, offset, "#{helper}()")
        repaired + "\ndef #{helper} : #{type}\n  #{helper}()\nend\n"
      end

      private def self.call_repair(
        text : String,
        context : Compiler::Editor::Context,
        offset : Int32,
        hole : String,
      ) : String
        before = text.byte_slice(0, offset)
        after = text.byte_slice(offset, text.bytesize - offset)
        if after.lstrip.starts_with?(')')
          return before + hole + after
        end

        before + hole + closing_parentheses(context) + after
      end

      private def self.closing_parentheses(context : Compiler::Editor::Context) : String
        context.call_name ? ")" : ""
      end

      private def self.semantic_receiver(
        snapshot : Compiler::Snapshot,
        path : String,
        span : Compiler::Editor::Context::Span,
      ) : Compiler::Editor::Index::Receiver?
        return unless span.end_offset > span.start_offset
        snapshot.editor_index.receiver_at(path, span.end_offset - 1) ||
          snapshot.editor_index.receiver_at(path, span.start_offset)
      end
    end
  end
end
