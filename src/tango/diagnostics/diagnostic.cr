module Tango
  struct Diagnostic
    enum FixKind
      PrefixUnusedLocal
    end

    alias FixEdit = Source::Edit
    record Fix, kind : FixKind, title : String, edits : Array(FixEdit)

    enum Severity
      Error
      Warning
    end

    enum Origin
      Frontend
      Emit
      Lint
      Check
    end

    getter origin : Origin
    getter severity : Severity
    getter code : String
    getter message : String
    getter file : String?
    getter line : Int32
    getter column : Int32
    getter size : Int32
    getter detail : String?
    getter unnecessary : Bool
    getter range : Source::Range?
    getter related : Array({Source::Range, String})
    getter hints : Array(String)
    getter fix : Fix?

    def initialize(
      @origin : Origin,
      @severity : Severity,
      @code : String,
      @message : String,
      @file : String? = nil,
      @line : Int32 = 1,
      @column : Int32 = 1,
      @size : Int32 = 1,
      @detail : String? = nil,
      @unnecessary : Bool = false,
      @range : Source::Range? = nil,
      @related : Array({Source::Range, String}) = [] of {Source::Range, String},
      @hints : Array(String) = [] of String,
      @fix : Fix? = nil,
    )
    end

    def self.from(ex : EmitError) : Diagnostic
      new(Origin::Emit, Severity::Error, Diagnostics::EMIT_UNSUPPORTED, ex.message.to_s)
    end

    def applies_to?(path : String) : Bool
      diagnostic_file = file
      diagnostic_file.nil? || diagnostic_file.empty? || diagnostic_file == path
    end

    def to_s(io : IO) : Nil
      case origin
      in .frontend?
        io << (detail || message)
      in .emit?
        if diagnostic_file = @file
          io << diagnostic_file << ':' << line << ':' << column << ": error: " << message
        else
          io << Diagnostics::EMIT_PREFIX << message
        end
      in .lint?
        io << file << ':' << line << ':' << column << ": warning: " << message
      in .check?
        if diagnostic_file = @file
          io << diagnostic_file << ':' << line << ':' << column << ": error: " << message
        else
          io << Diagnostics::CLI_PREFIX << message
        end
      end
    end
  end
end
