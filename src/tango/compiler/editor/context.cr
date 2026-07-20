module Tango
  module Compiler
    module Editor
      # A lightweight lexical view of the current buffer at one cursor. It does
      # not parse, type-check, or repair source; both completion and signature
      # help share this exact context so broken-buffer behavior cannot diverge.
      class Context
        enum CompletionKind
          None
          Require
          Bare
          Member
        end

        record Span, start_offset : Int32, end_offset : Int32

        getter completion_kind : CompletionKind
        getter prefix : String
        getter replacement : Span
        getter receiver : Span?
        getter call_name : String?
        getter call_name_span : Span?
        getter call_receiver : Span?
        getter active_parameter : Int32

        def self.at(text : String, cursor : Int32) : self
          new(text, cursor.clamp(0, text.bytesize))
        end

        private def initialize(@text : String, @cursor : Int32)
          quote_start, in_comment = lexical_region
          @call_name = nil
          @call_name_span = nil
          @call_receiver = nil
          @active_parameter = 0

          if quote_start
            if require_string?(quote_start)
              @completion_kind = CompletionKind::Require
              @prefix = @text.byte_slice(quote_start + 1, @cursor - quote_start - 1)
              @replacement = Span.new(quote_start + 1, string_content_end(quote_start))
            else
              empty_completion
              find_call_context
            end
            return
          end

          if in_comment
            empty_completion
            return
          end

          prefix_start = identifier_start(@cursor)
          @prefix = @text.byte_slice(prefix_start, @cursor - prefix_start)
          @replacement = Span.new(prefix_start, @cursor)
          if prefix_start > 0 && @text.byte_at(prefix_start - 1) == '.'.ord
            receiver_end = prefix_start - 1
            receiver_start = receiver_start(receiver_end)
            if receiver_start < receiver_end
              @completion_kind = CompletionKind::Member
              @receiver = Span.new(receiver_start, receiver_end)
            else
              @completion_kind = CompletionKind::None
              @receiver = nil
            end
          else
            @completion_kind = CompletionKind::Bare
            @receiver = nil
          end

          find_call_context
        end

        private def empty_completion : Nil
          @completion_kind = CompletionKind::None
          @prefix = ""
          @replacement = Span.new(@cursor, @cursor)
          @receiver = nil
        end

        # Returns the opening quote when the cursor is in a string and whether it
        # is in a line comment. Escaped quote bytes stay inside their string.
        private def lexical_region : {Int32?, Bool}
          quote = 0_u8
          quote_start = nil.as(Int32?)
          escaped = false
          comment = false
          index = 0
          while index < @cursor
            byte = @text.byte_at(index)
            if comment
              comment = false if byte == '\n'.ord
            elsif quote != 0
              if escaped
                escaped = false
              elsif byte == '\\'.ord
                escaped = true
              elsif byte == quote
                quote = 0_u8
                quote_start = nil
              end
            elsif byte == '#'.ord
              comment = true
            elsif byte == '"'.ord || byte == '\''.ord
              quote = byte
              quote_start = index
            end
            index += 1
          end
          {quote == 0 ? nil : quote_start, comment}
        end

        private def require_string?(quote_start : Int32) : Bool
          line_start = @text.rindex('\n', quote_start - 1).try(&.+(1)) || 0
          before = @text.byte_slice(line_start, quote_start - line_start).strip
          before == "require"
        end

        private def string_content_end(quote_start : Int32) : Int32
          quote = @text.byte_at(quote_start)
          escaped = false
          index = @cursor
          while index < @text.bytesize
            byte = @text.byte_at(index)
            if escaped
              escaped = false
            elsif byte == '\\'.ord
              escaped = true
            elsif byte == quote
              return index
            elsif byte == '\n'.ord
              return @cursor
            end
            index += 1
          end
          @cursor
        end

        private def find_call_context : Nil
          opens = [] of Int32
          quote = 0_u8
          escaped = false
          comment = false
          index = 0
          while index < @cursor
            byte = @text.byte_at(index)
            if comment
              comment = false if byte == '\n'.ord
            elsif quote != 0
              if escaped
                escaped = false
              elsif byte == '\\'.ord
                escaped = true
              elsif byte == quote
                quote = 0_u8
              end
            elsif byte == '#'.ord
              comment = true
            elsif byte == '"'.ord || byte == '\''.ord
              quote = byte
            elsif byte == '('.ord
              opens << index
            elsif byte == ')'.ord
              opens.pop unless opens.empty?
            end
            index += 1
          end

          open = opens.last?
          return unless open
          name_end = skip_space_backward(open)
          name_start = identifier_start(name_end)
          return if name_start == name_end

          @call_name = @text.byte_slice(name_start, name_end - name_start)
          @call_name_span = Span.new(name_start, name_end)
          if name_start > 0 && @text.byte_at(name_start - 1) == '.'.ord
            receiver_end = name_start - 1
            start = receiver_start(receiver_end)
            @call_receiver = Span.new(start, receiver_end) if start < receiver_end
          end
          @active_parameter = active_parameter_after(open)
        end

        private def active_parameter_after(open : Int32) : Int32
          nested = 0
          active = 0
          quote = 0_u8
          escaped = false
          comment = false
          index = open + 1
          while index < @cursor
            byte = @text.byte_at(index)
            if comment
              comment = false if byte == '\n'.ord
            elsif quote != 0
              if escaped
                escaped = false
              elsif byte == '\\'.ord
                escaped = true
              elsif byte == quote
                quote = 0_u8
              end
            elsif byte == '#'.ord
              comment = true
            elsif byte == '"'.ord || byte == '\''.ord
              quote = byte
            elsif byte == '('.ord || byte == '['.ord || byte == '{'.ord
              nested += 1
            elsif byte == ')'.ord || byte == ']'.ord || byte == '}'.ord
              nested -= 1 if nested > 0
            elsif byte == ','.ord && nested == 0
              active += 1
            end
            index += 1
          end
          active
        end

        private def skip_space_backward(offset : Int32) : Int32
          index = offset
          while index > 0 && whitespace?(@text.byte_at(index - 1))
            index -= 1
          end
          index
        end

        private def identifier_start(offset : Int32) : Int32
          index = offset
          while index > 0 && identifier_byte?(@text.byte_at(index - 1))
            index -= 1
          end
          index
        end

        private def receiver_start(offset : Int32) : Int32
          index = skip_space_backward(offset)
          while index > 0 && receiver_byte?(@text.byte_at(index - 1))
            index -= 1
          end
          index
        end

        private def identifier_byte?(byte : UInt8) : Bool
          byte.in?('a'.ord..'z'.ord) || byte.in?('A'.ord..'Z'.ord) ||
            byte.in?('0'.ord..'9'.ord) || byte == '_'.ord || byte == '?'.ord || byte == '!'.ord
        end

        private def receiver_byte?(byte : UInt8) : Bool
          identifier_byte?(byte) || byte == '@'.ord || byte == ':'.ord
        end

        private def whitespace?(byte : UInt8) : Bool
          byte == ' '.ord || byte == '\t'.ord || byte == '\r'.ord || byte == '\n'.ord
        end
      end
    end
  end
end
