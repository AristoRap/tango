module Tango
  module Target
    module Go
      module Runtime
        class Import < Requirement
          getter path : String

          def initialize(@path : String)
          end

          def key : String
            "import:#{path}"
          end
        end
      end
    end
  end
end
