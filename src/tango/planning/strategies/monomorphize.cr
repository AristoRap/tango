module Tango
  module Planning
    module Strategies
      # Assigns each top-level def instance its monomorphized function name,
      # keyed by its concrete parameter-type signature. The frontend already
      # drained one NIR::Def per concrete instantiation (deduped by object_id),
      # so a name that owns several signatures arrives as several Def nodes;
      # this strategy just names each one. Call sites are routed to the
      # matching name by Strategies::Calls via the same Mangle helper.
      class Monomorphize
        def self.run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          new.run(program, facts, table)
        end

        def run(program : IR::NIR::Program, facts : Analysis::Facts::Table, table : Plans::Table) : Nil
          program.body.each do |stmt|
            next unless stmt.is_a?(IR::NIR::Def)

            signature = stmt.params.map { |param| param.type || IR::Type.unknown }
            mode = Plans::BlockMode::Plain
            stmt.block_param.try do |block_param|
              signature << block_param.signature.to_type
              mode = block_mode(block_param)
            end
            table.monomorphs[stmt.id] = Plans::DefPlan.new(Mangle.func_name(stmt.name, signature, stmt.namespace_path), mode)
          end
        end

        private def block_mode(param : IR::NIR::BlockParam) : Plans::BlockMode
          unless param.yield_parameter?
            return param.signature.return_type ? Plans::BlockMode::Value : Plans::BlockMode::Plain
          end
          Plans::BlockMode.for_yield(param.value_required?)
        end
      end
    end
  end
end
