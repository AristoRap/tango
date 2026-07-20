module Tango
  module Frontend
    module Crystal
      # Tango owns the user-facing spelling of Crystal frontend failures; the
      # host's full message remains diagnostic detail for debugging. Keep this
      # presentation-only: it never derives types or source locations anew.
      module DiagnosticMessage
        def self.render(message : String) : String
          chars = message.chars
          String.build do |io|
            index = 0
            while index < chars.size
              if root_qualifier?(chars, index)
                index += 2
              else
                io << chars[index]
                index += 1
              end
            end
          end
        end

        private def self.root_qualifier?(chars : Array(Char), index : Int32) : Bool
          return false unless chars[index] == ':' && chars[index + 1]? == ':'
          return false unless name_start?(chars[index + 2]?)

          previous = index > 0 ? chars[index - 1] : nil
          previous.nil? || previous.whitespace? || previous.in?('\'', '"', '(', '[', '{')
        end

        private def self.name_start?(char : Char?) : Bool
          return false unless char
          char.in?('a'..'z') || char == '_'
        end
      end
    end
  end
end
