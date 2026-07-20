module Tango
  module Planning
    class Driver
      def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, profile : Compiler::CompilationProfile = Compiler::CompilationProfile::Development) : Plans::Table
        new.run(program, facts, profile)
      end

      def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, profile : Compiler::CompilationProfile = Compiler::CompilationProfile::Development) : Plans::Table
        table = Plans::Table.new
        Strategies::Layout.run(program, facts, table)
        Strategies::Enums.run(program, facts, table)
        Strategies::Repr.run(program, facts, table)
        Strategies::UnionConversions.run(program, facts, table)
        Strategies::Arrays.run(program, facts, table)
        Strategies::Hashes.run(program, facts, table)
        Strategies::CoreDispatch.run(program, facts, table)
        Strategies::Numeric.run(program, facts, table)
        Strategies::Monomorphize.run(program, facts, table)
        Strategies::Capabilities.run(program, facts, table)
        Strategies::Calls.run(program, facts, table)
        Strategies::Constructors.run(program, facts, table)
        Strategies::Blocks.run(program, facts, table)
        Strategies::Exceptions.run(program, facts, table)
        Strategies::Stringifications.run(program, facts, table)
        Strategies::Cardinalities.run(program, facts, table)
        Strategies::CollectionProductions.run(program, facts, table, profile)
        Strategies::SemanticCollections.run(program, facts, table, profile)
        table
      end
    end
  end
end
