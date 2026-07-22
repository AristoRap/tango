module Tango
  module Target
    module Go
      module Runtime
        # One Go module input required by emitted imports. It is build metadata,
        # never source text: the toolchain renders it into the generated go.mod.
        class ModuleRequirement < Requirement
          getter path : String
          getter version : String
          getter local_path : String?

          def initialize(@path : String, @version : String, @local_path : String? = nil)
          end

          def key : String
            "module:#{path}:#{version}:#{local_path}"
          end
        end
      end
    end
  end
end
