module Tango
  module Target
    module Go
      module Runtime
        class Import < Requirement
          getter path : String
          getter identifier : String?

          def initialize(@path : String, @identifier : String? = nil)
          end

          def key : String
            "import:#{path}:#{identifier}"
          end
        end
      end
    end
  end
end
