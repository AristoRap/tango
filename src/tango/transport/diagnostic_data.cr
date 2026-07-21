module Tango
  module Transport
    @[JSON::Serializable::Options(emit_nulls: true)]
    class RelatedDiagnosticData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter range : RangeData
      getter message : String

      def initialize(range : Source::Range, @message : String)
        @range = RangeData.new(range)
      end

      def to_related : {Source::Range, String}
        {@range.to_range, @message}
      end
    end

    @[JSON::Serializable::Options(emit_nulls: true)]
    class DiagnosticFixEditData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter range : RangeData
      getter new_text : String

      def initialize(edit : Diagnostic::FixEdit)
        @range = RangeData.new(edit.range)
        @new_text = edit.new_text
      end

      def to_edit : Diagnostic::FixEdit
        Diagnostic::FixEdit.new(@range.to_range, @new_text)
      end
    end

    @[JSON::Serializable::Options(emit_nulls: true)]
    class DiagnosticFixData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter kind : String
      getter title : String
      getter edits : Array(DiagnosticFixEditData)

      def initialize(fix : Diagnostic::Fix)
        @kind = fix.kind.to_s
        @title = fix.title
        @edits = fix.edits.map { |edit| DiagnosticFixEditData.new(edit) }
      end

      def to_fix : Diagnostic::Fix
        Diagnostic::Fix.new(
          Diagnostic::FixKind.parse(@kind),
          @title,
          @edits.map(&.to_edit)
        )
      end
    end

    @[JSON::Serializable::Options(emit_nulls: true)]
    class DiagnosticData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter origin : String
      getter severity : String
      getter code : String
      getter message : String
      getter file : String?
      getter line : Int32
      getter column : Int32
      getter size : Int32
      getter detail : String?
      getter unnecessary : Bool
      getter range : RangeData?
      getter related : Array(RelatedDiagnosticData)
      getter hints : Array(String)
      getter fix : DiagnosticFixData?

      def initialize(diagnostic : Diagnostic)
        @origin = diagnostic.origin.to_s
        @severity = diagnostic.severity.to_s
        @code = diagnostic.code
        @message = diagnostic.message
        @file = diagnostic.file
        @line = diagnostic.line
        @column = diagnostic.column
        @size = diagnostic.size
        @detail = diagnostic.detail
        @unnecessary = diagnostic.unnecessary
        @range = diagnostic.range.try { |range| RangeData.new(range) }
        @related = diagnostic.related.map { |range, message| RelatedDiagnosticData.new(range, message) }
        @hints = diagnostic.hints
        @fix = diagnostic.fix.try { |fix| DiagnosticFixData.new(fix) }
      end

      def to_diagnostic : Diagnostic
        Diagnostic.new(
          Diagnostic::Origin.parse(@origin),
          Diagnostic::Severity.parse(@severity),
          @code,
          @message,
          @file,
          @line,
          @column,
          @size,
          @detail,
          @unnecessary,
          @range.try(&.to_range),
          @related.map(&.to_related),
          hints: @hints,
          fix: @fix.try(&.to_fix)
        )
      end
    end
  end
end
