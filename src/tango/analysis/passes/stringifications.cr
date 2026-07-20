module Tango
  module Analysis
    module Passes
      # Classifies interpolation pieces using Crystal-resolved NIR types. A
      # missing fact is deliberate rejection: the piece is not scalar surface
      # owned by this milestone.
      class Stringifications
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          IR::NIR::Walk.children(program).each { |node| visit(node, table) }
        end

        private def self.visit(node : IR::NIR::Stmt, table : Facts::Table) : Nil
          if node.is_a?(IR::NIR::Interpolation)
            node.pieces.each do |piece|
              type = piece.type
              table.scalar_stringifications[piece.id] = Facts::ScalarStringification.new(type) if type && scalar?(type)
            end
          end
          IR::NIR::Walk.children(node).each { |child| visit(child, table) }
        end

        private def self.scalar?(type : IR::Type) : Bool
          type.family.int? || type.family.float? || type.family.bool? || type.family.string? || type.family.null?
        end
      end
    end
  end
end
