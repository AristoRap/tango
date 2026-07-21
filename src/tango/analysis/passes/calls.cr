module Tango
  module Analysis
    module Passes
      class Calls
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          definitions = Hash(Facts::CallableSignature, IR::NIR::Def).new
          IR::NIR::Walk.children(program).each do |stmt|
            next unless stmt.is_a?(IR::NIR::Def)
            definitions[signature(stmt)] = stmt
          end

          IR::NIR::Walk.children(program).each { |stmt| visit(stmt, definitions, table) }
        end

        private def visit(node : IR::NIR::Stmt, definitions : Hash(Facts::CallableSignature, IR::NIR::Def), table : Facts::Table) : Nil
          call_signature = case node
                           when IR::NIR::Call
                             signature(node) unless node.primitive
                           when IR::NIR::SemanticOperation
                             signature(node.fallback)
                           when IR::NIR::New
                             signature(node) if node.invokes_initializer?
                           end
          if call_signature && (definition = definitions[call_signature]?)
            table.internal_calls[node.id] = Facts::ResolvedCall.new(definition.id, call_signature)
          end

          IR::NIR::Walk.children(node).each { |child| visit(child, definitions, table) }
        end

        private def signature(node : IR::NIR::Def) : Facts::CallableSignature
          parameter_types = node.params.map { |param| param.type || IR::Type.unknown }
          node.block_param.try { |block| parameter_types << block.signature.to_type }
          Facts::CallableSignature.new(node.name, parameter_types, node.namespace_path)
        end

        private def signature(node : IR::NIR::Call) : Facts::CallableSignature
          parameter_types = node.args.map { |arg| arg.type || IR::Type.unknown }
          node.block.try { |block| parameter_types << block.signature.to_type }
          owner_path = node.targets.find { |target| target.name == node.name && !target.owner_path.empty? }.try(&.owner_path) || [] of String
          Facts::CallableSignature.new(node.name, parameter_types, owner_path)
        end

        private def signature(node : IR::NIR::New) : Facts::CallableSignature
          owner = node.type || IR::Type.klass(node.class_name)
          parameter_types = [owner] of IR::Type
          parameter_types.concat(node.args.map { |arg| arg.type || IR::Type.unknown })
          Facts::CallableSignature.new("initialize", parameter_types)
        end
      end
    end
  end
end
