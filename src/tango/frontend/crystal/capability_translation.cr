module Tango
  module Frontend
    module Crystal
      module CapabilityTranslation
        # Crystal has already checked module inclusion and abstract requirements
        # by this point. Preserve both ways that proof reaches a typed def:
        # a capability-restricted argument specialized to a concrete type, and
        # an ordinary body inherited from a module into its concrete owner.
        private def capability_witnesses(node : ::Crystal::Def) : Array(IR::CapabilityConformance)
          witnesses = [] of IR::CapabilityConformance
          owner = node.owner?

          if owner && (original_owner = node.original_owner?) && original_owner.module? && owner != original_owner
            capability = instantiated_capability(owner, original_owner)
            witnesses << IR::CapabilityConformance.new(build_type(owner), build_type(capability))
          end

          if owner
            free_vars = solved_free_vars(node)
            node.args.each do |arg|
              restriction = arg.restriction
              concrete = arg.type?
              next unless restriction && concrete

              capability = owner.lookup_type?(restriction, owner, true, free_vars)
              next unless capability && capability.module?

              witness = IR::CapabilityConformance.new(build_type(concrete), build_type(capability))
              witnesses << witness unless witnesses.includes?(witness)
            end
          end

          witnesses
        end

        # A specialized generic def keeps its source restrictions (`T`,
        # `Comparable(T)`) while argument types carry the solved values. Feed
        # those values back through Crystal's own type lookup rather than
        # reconstructing a generic capability from names.
        private def solved_free_vars(node : ::Crystal::Def) : Hash(String, ::Crystal::TypeVar)?
          names = node.free_vars
          return nil unless names

          solved = {} of String => ::Crystal::TypeVar
          node.args.each do |arg|
            restriction = arg.restriction
            name = restriction.try { |value| value.as?(::Crystal::Path).try(&.single_name?) }
            type = arg.type?
            solved[name] = type if name && type && names.includes?(name)
          end
          solved.empty? ? nil : solved
        end

        # Crystal retains a generic module definition such as Comparable(T) as
        # a cloned method's original owner. The concrete receiver's ancestors
        # carry the solved inclusion, such as Comparable(Float64); preserve that
        # instance so downstream capability identity never leaks a free T.
        private def instantiated_capability(owner : ::Crystal::Type, original_owner : ::Crystal::Type) : ::Crystal::Type
          original_generic = original_owner.is_a?(::Crystal::GenericInstanceType) ? original_owner.generic_type : original_owner
          owner.ancestors.find do |ancestor|
            ancestor_generic = ancestor.is_a?(::Crystal::GenericInstanceType) ? ancestor.generic_type : ancestor
            ancestor.module? && ancestor_generic == original_generic
          end || original_owner
        end
      end
    end
  end
end
