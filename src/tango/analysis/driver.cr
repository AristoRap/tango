module Tango
  module Analysis
    class Driver
      def self.run(program : IR::NIR::Program) : Facts::Table
        new.run(program)
      end

      def run(program : IR::NIR::Program) : Facts::Table
        table = Facts::Table.new
        Passes::Types.run(program, table)
        Passes::Declarations.run(program, table)
        Passes::Annotations.run(program, table)
        Passes::Calls.run(program, table)
        Passes::Capabilities.run(program, table)
        Passes::UnionFlows.run(program, table)
        Passes::Layout.run(program, table)
        Passes::Enums.run(program, table)
        Passes::Comparability.run(program, table)
        Passes::CoreDispatch.run(program, table)
        Passes::References.run(program, table)
        Passes::Blocks.run(program, table)
        Passes::Stringifications.run(program, table)
        Passes::CollectionUses.run(program, table)
        Passes::CollectionLegality.run(program, table)
        Passes::Traversals.run(program, table)
        table
      end
    end
  end
end
