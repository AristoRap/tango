module Tango
  module Dump
    module Facts
      def self.render(snapshot : Compiler::Snapshot) : String
        facts = snapshot.facts
        return "" unless facts
        locations = SourceLocations.index(snapshot.nir)

        String.build do |io|
          SourceGraphHeader.append(io, snapshot.source)
          facts.types.expressions.each do |id, type|
            io << id << " type " << type
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.types.unions.each { |union| io << "union_type " << union << '\n' }
          facts.types.arrays.each { |array| io << "array_type " << array << '\n' }
          facts.types.hashes.each { |hash| io << "hash_type " << hash << '\n' }
          facts.enums.each_value do |definition|
            io << "enum " << definition.type << " base=" << definition.base_type
            definition.members.each { |member| io << " (" << member.name << '=' << member.value << ')' }
            io << '\n'
          end
          facts.namespaces.each do |id, definition|
            io << id << " namespace " << definition.path.join("::")
            definition.parent.try { |parent| io << " parent=" << parent.join("::") }
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.namespace_owners.each do |id, path|
            io << id << " namespace_owner " << path.join("::")
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.constants.each_value do |definition|
            io << definition.declaration << " constant " << definition.path.join("::") << " : " << definition.type
            SourceLocations.append(io, locations[definition.declaration]?)
            io << '\n'
          end
          facts.type_aliases.each_value do |definition|
            io << definition.declaration << " type_alias " << definition.path.join("::") << " = " << definition.target
            SourceLocations.append(io, locations[definition.declaration]?)
            io << '\n'
          end
          facts.external_types.each do |type, binding|
            io << type << " external_type " << binding.binding.language << " " << binding.shape
            binding.binding.package_name.try { |package_name| io << " package=" << package_name }
            binding.binding.name.try { |name| io << " name=" << name }
            io << '\n'
          end
          facts.comparabilities.each do |type, verdict|
            io << type << " comparability " << verdict.class.name.split("::").last
            case verdict
            when Analysis::Facts::GoRejects, Analysis::Facts::WrongSemantics
              io << " " << verdict.reason
            end
            io << '\n'
          end
          facts.dispatch_relations.each do |id, relation|
            io << id << " dispatch " << relation.source << " -> " << relation.target << " " << relation.relation
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.union_flows.each do |id, flow|
            io << id << " union_flow " << flow.source << " -> " << flow.target
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.go_externals.each do |id, callees|
            callees.each do |callee|
              io << id << " go_external " << callee
              SourceLocations.append(io, locations[id]?)
              io << '\n'
            end
          end
          facts.internal_calls.each do |id, resolved|
            io << id << " internal_call " << resolved.name
            io << '(' << resolved.signature.parameter_types.join(", ") << ") -> " << resolved.definition
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.capability_conformances.each do |id, conformances|
            conformances.each do |conformance|
              io << id << " capability_conformance " << conformance.concrete << " as " << conformance.capability
              SourceLocations.append(io, locations[id]?)
              io << '\n'
            end
          end
          facts.struct_layouts.each do |name, layout|
            io << name << " struct_layout " << (layout.reference ? "reference " : "value ")
            io << layout.fields.map { |field| "#{field.name} : #{field.type}" }.join(", ") << '\n'
          end
          facts.exception_hierarchies.each do |name, hierarchy|
            io << name << " exception_hierarchy " << hierarchy.ancestors.join(" < ") << '\n'
          end
          facts.references.each do |id, reference|
            case reference
            when Analysis::Facts::ClassReference
              io << id << " type_ref " << reference.name
            when Analysis::Facts::FieldReference
              io << id << " field_ref " << reference.owner << '.' << reference.field
            when Analysis::Facts::LocalReference
              io << id << " local_ref " << reference.declaration
            when Analysis::Facts::EnumMemberReference
              io << id << " enum_member_ref " << reference.enum_type << "::" << reference.member
            when Analysis::Facts::ConstantReference
              io << id << " constant_ref " << reference.path.join("::") << " -> " << reference.declaration
            when Analysis::Facts::TypeAliasReference
              io << id << " type_alias_ref " << reference.path.join("::") << " -> " << reference.declaration
            end
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.local_bindings.each do |id, binding|
            io << id << " local_binding " << binding.name
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.local_writes.each do |id, declaration|
            io << id << " local_write " << declaration
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.binding_uses.each { |id| io << id << " binding_use\n" }
          facts.local_reads.each { |id| io << id << " local_read\n" }
          facts.unread_local_writes.each do |id|
            io << id << " unread_local_write"
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.unused_locals.each do |id|
            binding = facts.local_bindings[id]
            io << id << " unused_local " << binding.name
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.blocks.each do |id, block|
            io << id << " block captures=[" << block.captured.map(&.name).join(", ") << "]"
            io << " escapes=" << block.escapes
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.scalar_stringifications.each do |id, fact|
            io << id << " scalar_stringification " << fact.type
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.collection_uses.each do |producer, uses|
            uses.each do |use|
              io << producer << " collection_use " << use.kind << " consumer=" << use.consumer
              io << " path=" << use.path
              SourceLocations.append(io, locations[producer]?)
              io << '\n'
            end
          end
          facts.semantic_collections.each do |id, fact|
            io << id << " semantic_collection_facts"
            io << " escapes=" << fact.intermediate_escapes
            io << " effects=[" << fact.block.effects.join(", ") << ']'
            io << " may_raise=" << fact.block.may_raise
            io << " captured_mutation=" << fact.block.captured_mutation
            io << " abrupt=" << fact.block.abrupt_control_flow
            io << " order=" << fact.encounter_order
            io << " replay=" << fact.replayability
            io << " finiteness=" << fact.finiteness
            io << " input=" << render_cardinality(fact.input_cardinality)
            output = fact.output_cardinality.try { |bounds| render_cardinality(bounds) } || "terminal"
            io << " output=" << output
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          facts.traversals.each do |id, fact|
            io << id << " traversal_facts"
            io << " blocking=" << fact.blocking
            io << " consumption=" << fact.consumption
            io << " replay=" << fact.replayability
            io << " finiteness=" << fact.finiteness
            io << " order=" << fact.encounter_order
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
        end
      end

      private def self.render_cardinality(bounds : Analysis::Facts::CardinalityBounds) : String
        minimum = bounds.minimum
        maximum = bounds.maximum
        return minimum.to_s if minimum && maximum && minimum == maximum
        return "unknown" unless minimum || maximum
        "#{minimum || "?"}..#{maximum || "?"}"
      end
    end
  end
end
