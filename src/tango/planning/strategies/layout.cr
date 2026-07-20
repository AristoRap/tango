module Tango
  module Planning
    module Strategies
      # Chooses each class's representation from its proven layout. Classes are
      # reference types, so they lower to pointer-backed structs (Decisions
      # log). A `struct` value type would choose otherwise — no driving example
      # forces it yet.
      class Layout
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          facts.struct_layouts.each do |name, layout|
            fields = layout.fields.dup
            ancestors = facts.exception_hierarchies[name]?.try(&.ancestors) || [] of String
            table.layouts[name] = Plans::ClassLayout.new(
              name,
              fields,
              reference: layout.reference,
              exception_ancestors: ancestors,
              identity_padding: layout.reference && fields.empty?
            )
          end
        end
      end
    end
  end
end
