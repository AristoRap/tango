module Tango
  module Target
    module Go
      module Runtime
        class Helper < Requirement
          getter name : String

          def initialize(@name : String)
          end

          def key : String
            "helper:#{name}"
          end

          def snippet : Snippet
            Registry.snippet(name)
          end

          def requires : Array(Requirement)
            requirements = [] of Requirement
            snippet.deps.each { |dep| requirements << Helper.new(dep) }
            snippet.imports.each { |path| requirements << Import.new(path) }
            requirements
          end
        end
      end
    end
  end
end
