module Tango
  module Planning
    module Strategies
      class CoreDispatch
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          program.body.each { |node| visit(node, facts, table) }
        end

        private def visit(node : IR::NIR::Stmt, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          case node
          when IR::NIR::Call
            if node.primitive && node.name.in?("==", "!=", "===")
              arg = node.args.first?
              type = (arg && facts.types.expressions[arg.id]?) || IR::Type.unknown
              if facts.comparabilities[type]?.is_a?(Analysis::Facts::Comparable)
                table.equalities[node.id] = Plans::EqualityStrategy::Native
              end
            end
          when IR::NIR::TypeTest
            plan_type_test(node, facts, table).try { |plan| table.type_tests[node.id] = plan }
          when IR::NIR::Cast
            plan_cast(node, facts, table).try { |plan| table.casts[node.id] = plan }
          end
          IR::NIR::Walk.non_binding_children(node).each { |child| visit(child, facts, table) }
        end

        private def plan_type_test(node : IR::NIR::TypeTest, facts : Analysis::Facts::Table, table : Plans::Table) : Plans::TypeTestPlan?
          relation = facts.dispatch_relations[node.id]?
          return nil unless relation
          strategy = case relation.relation
                     when .exact?, .widening?
                       Plans::TypeTestPlan::Strategy::StaticTrue
                     when .impossible?
                       Plans::TypeTestPlan::Strategy::StaticFalse
                     when .member?
                       case table.reprs[relation.source]?
                       when Plans::CarrierRepr
                         relation.target.nil_type? ? Plans::TypeTestPlan::Strategy::CarrierNil : Plans::TypeTestPlan::Strategy::CarrierTag
                       when Plans::PointerRepr
                         relation.target.nil_type? ? Plans::TypeTestPlan::Strategy::PointerNil : Plans::TypeTestPlan::Strategy::PointerNonNil
                       end
                     end
          strategy.try { |value| Plans::TypeTestPlan.new(value, relation.source, relation.target) }
        end

        private def plan_cast(node : IR::NIR::Cast, facts : Analysis::Facts::Table, table : Plans::Table) : Plans::CastPlan?
          relation = facts.dispatch_relations[node.id]?
          return nil unless relation
          strategy = case relation.relation
                     when .exact?, .widening?
                       Plans::CastPlan::Strategy::Passthrough
                     when .member?
                       case table.reprs[relation.source]?
                       when Plans::CarrierRepr then Plans::CastPlan::Strategy::CarrierChecked
                       when Plans::PointerRepr then Plans::CastPlan::Strategy::PointerChecked
                       end
                     when .impossible?
                       nil
                     end
          strategy.try { |value| Plans::CastPlan.new(value, relation.source, relation.target) }
        end
      end
    end
  end
end
