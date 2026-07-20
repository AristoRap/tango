module Tango
  module Frontend
    module Bundle
      # Raised before a bundle can enter the compiler core. Compatibility is
      # exact until a migration path is introduced deliberately.
      class UnsupportedVersionError < Exception
        getter actual : Int32
        getter supported : Int32

        def initialize(@actual : Int32, @supported : Int32)
          super("unsupported semantic bundle schema version #{@actual}; supported version is #{@supported}")
        end
      end

      # One structured failure for malformed schema-v1 wire data. Unsupported
      # versions retain their distinct error so callers can separate an upgrade
      # requirement from corrupt input without parsing messages.
      class CodecError < Exception
        getter location : String

        def initialize(@location : String, detail : String)
          super("invalid semantic bundle at #{@location}: #{detail}")
        end
      end
    end
  end
end
