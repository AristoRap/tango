module Tango
  module Dump
    module Plans
      def self.render(snapshot : Compiler::Snapshot) : String
        plans = snapshot.plans
        return "" unless plans
        locations = SourceLocations.index(snapshot.nir)

        String.build do |io|
          SourceGraphHeader.append(io, snapshot.source)
          plans.uncaught_exception.try { |strategy| io << "uncaught_exception " << strategy << '\n' }
          plans.layouts.each do |name, plan|
            io << name << " layout " << (plan.reference ? "ClassLayout" : "StructLayout")
            io << " { " << plan.fields.map { |field| "#{field.name} : #{field.type}" }.join(", ") << " }" unless plan.fields.empty?
            io << " exception_runtime=[#{plan.exception_ancestors.join(" < ")}]" if plan.exception_runtime?
            io << " identity_padding" if plan.identity_padding?
            io << '\n'
          end
          plans.reprs.each do |type, repr|
            io << type << " repr " << render_repr(repr) << '\n'
          end
          plans.arrays.each do |type, repr|
            io << type << " array_repr " << (repr.reference? ? "PointerSlice" : "Slice")
            io << " element=" << repr.element << '\n'
          end
          plans.hashes.each do |type, repr|
            io << type << " hash_repr " << (repr.reference? ? "Reference" : "Value")
            io << " order=" << (repr.ordered? ? "Insertion" : "Unspecified")
            io << " key=" << repr.key << " value=" << repr.value << '\n'
          end
          plans.enums.each_value do |repr|
            io << "enum_repr " << repr.type << " NominalInteger base=" << repr.base_type
            io << " target=" << repr.target_name
            repr.members.each { |member| io << " (" << member.name << '=' << member.value << " -> " << member.target_name << ')' }
            io << '\n'
          end
          plans.namespaces.each_value do |plan|
            io << "namespace " << plan.path.join("::") << " target=" << plan.target_prefix << '\n'
          end
          plans.type_aliases.each_value do |plan|
            io << "type_alias " << plan.path.join("::") << " = " << plan.target << '\n'
          end
          plans.constants.each_value do |plan|
            io << "constant " << plan.path.join("::") << " target=" << plan.target_name << " type=" << plan.type << '\n'
          end
          plans.equalities.each do |id, strategy|
            io << id << " equality " << strategy
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.checked_arithmetic.each do |id, plan|
            io << id << " checked_arithmetic " << plan.strategy
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.type_tests.each do |id, plan|
            io << id << " type_test " << plan.strategy << " " << plan.source << " -> " << plan.target
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.casts.each do |id, plan|
            io << id << " cast " << plan.strategy << " " << plan.source << " -> " << plan.target
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.carrier_conversions.each do |id, plan|
            io << id << " carrier_conversion " << plan.mapping.name << " " << plan.source << " -> " << plan.target
            plan.mapping.variants.each do |variant|
              io << " (" << variant.member << ":" << variant.source_tag << "->" << variant.target_tag << ")"
            end
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.monomorphs.each do |id, plan|
            io << id << " def " << plan.name
            io << " block_mode=" << plan.block_mode
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.capability_dispatches.each do |id, dispatches|
            dispatches.each do |dispatch|
              io << id << " capability_dispatch " << dispatch.strategy
              io << ' ' << dispatch.concrete << " as " << dispatch.capability
              SourceLocations.append(io, locations[id]?)
              io << '\n'
            end
          end
          plans.constructors.each do |id, plan|
            io << id << " constructor " << plan.name
            plan.initialize_name.try { |name| io << " -> " << name }
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.calls.each do |id, plan|
            io << id << " call " << plan.class.name.split("::").last
            case plan
            when Planning::Plans::InternalCall
              io << ' ' << plan.name
            when Planning::Plans::ExternalGo
              io << ' ' << plan.callee
            end
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.closures.each do |id, plan|
            io << id << " closure mode=" << plan.mode
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.handlers.each do |id, plan|
            io << id << " handler " << plan.strategy
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.scalar_stringifications.each do |id, plan|
            io << id << " scalar_presentation " << plan.presentation << " " << plan.type
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.semantic_collections.each do |id, plan|
            io << id << " semantic_collection " << plan.class.name.split("::").last << " " << plan.result_type
            if fused = plan.as?(Planning::Plans::FusedCollectionTraversal)
              io << " source=" << fused.source
              io << " transforms=[" << fused.transforms.map(&.kind).join(", ") << ']'
              io << " terminal=" << fused.terminal
            end
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.collection_productions.each do |id, plan|
            io << id << " collection_production " << plan.class.name.split("::").last << " " << plan.type
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
          plans.cardinalities.each do |id, plan|
            io << id << " cardinality " << plan.class.name.split("::").last << " " << plan.source_type
            io << " source=" << plan.source if plan.is_a?(Planning::Plans::StoredCardinality)
            SourceLocations.append(io, locations[id]?)
            io << '\n'
          end
        end
      end

      private def self.render_repr(repr : Planning::Plans::Repr) : String
        case repr
        when Planning::Plans::PointerRepr
          "Pointer *#{repr.element}"
        when Planning::Plans::CarrierRepr
          variants = repr.variants.map do |variant|
            payload = variant.payload
            payload ? "#{variant.tag}:#{variant.label}(#{payload})" : "#{variant.tag}:#{variant.label}"
          end
          "Carrier #{repr.name} { #{variants.join(", ")} }"
        else
          repr.class.name.split("::").last
        end
      end
    end
  end
end
