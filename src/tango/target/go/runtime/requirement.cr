require "set"

module Tango
  module Target
    module Go
      module Runtime
        abstract class Requirement
          abstract def key : String

          def requires : Array(Requirement)
            [] of Requirement
          end

          def self.closure(items : Array(Requirement)) : Array(Requirement)
            seen = Set(String).new
            ordered = [] of Requirement
            items.each { |requirement| visit(requirement, seen, ordered) }
            ordered
          end

          private def self.visit(requirement : Requirement, seen : Set(String), ordered : Array(Requirement)) : Nil
            return if seen.includes?(requirement.key)

            seen << requirement.key
            requirement.requires.each { |dependency| visit(dependency, seen, ordered) }
            ordered << requirement
          end
        end
      end
    end
  end
end
