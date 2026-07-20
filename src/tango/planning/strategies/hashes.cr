module Tango
  module Planning
    module Strategies
      class Hashes
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.types.hashes.each do |type|
            key = type.key_type || IR::Type.unknown
            next unless facts.comparabilities[key]?.is_a?(Analysis::Facts::Comparable)
            table.hashes[type] = Plans::HashRepr.new(type, reference: true, ordered: true)
          end
        end
      end
    end
  end
end
