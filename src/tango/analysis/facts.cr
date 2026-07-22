module Tango
  module Analysis
    module Facts
      class GoExternal
        getter binding : IR::ExternalBinding
        getter dependency : IR::ExternalDependency?
        getter? receiver_method : Bool

        def initialize(package_identifier : String?, name : String, @receiver_method : Bool = false, import_path : String? = package_identifier, @dependency : IR::ExternalDependency? = nil)
          @binding = IR::ExternalBinding.new("go", package_identifier, name, import_path: import_path)
        end

        def initialize(@binding : IR::ExternalBinding, @receiver_method : Bool = false, @dependency : IR::ExternalDependency? = nil)
        end

        def import_path : String?
          binding.import_path
        end

        def package_identifier : String?
          binding.package_identifier
        end

        def name : String
          binding.name || ""
        end

        def self.parse(value : String) : self
          # A leading dot marks the method-binding form (`@[Go(".Lock")]`): the
          # call targets a method on its receiver (arriving as the first arg),
          # not a package function. The target spells the actual call.
          if value.starts_with?('.')
            return new(nil, value.lchop('.'), receiver_method: true)
          end

          new(IR::ExternalBinding.qualified("go", value))
        end

        def self.package(import_path : String, package_identifier : String, name : String, dependency : IR::ExternalDependency? = nil) : self
          new(IR::ExternalBinding.package("go", import_path, package_identifier, name), dependency: dependency)
        end

        def to_s(io : IO) : Nil
          if receiver_method?
            io << '.' << name
          elsif package_identifier = package_identifier()
            io << package_identifier << '.' << name
          else
            io << name
          end
        end
      end

      record Capture, declaration : NodeId, name : String
      record BlockFacts, captured : Array(Capture), escapes : Bool

      # A resolved scalar piece. Analysis records only that its type belongs to
      # Tango's scalar presentation surface.
      record ScalarStringification, type : IR::Type

      enum CollectionConsumer
        Size
        Map
        Filter
        Each
        Fold
      end

      enum CollectionUsePath
        Direct
        Aliased
      end

      # One semantic consumer of a collection-producing value, reached directly
      # or through a proven local alias. Planning decides its realization.
      record CollectionUse, consumer : NodeId, kind : CollectionConsumer, path : CollectionUsePath = CollectionUsePath::Direct

      enum CollectionBlockEffect
        LocalMutation
        CapturedMutation
        InstanceMutation
        CollectionMutation
        Call
        Concurrency
        Unknown
      end

      enum EncounterOrder
        Stable
        Unspecified
        Unknown
      end

      enum Replayability
        Replayable
        OneShot
        Unknown
      end

      enum Finiteness
        Finite
        Infinite
        Unknown
      end

      enum BlockingBehavior
        MayBlock
        NonBlocking
        Unknown
      end

      enum ConsumptionBehavior
        Destructive
        NonDestructive
        Unknown
      end

      # Laws of one structured traversal step. Consumption and blocking are
      # independent: a source can consume state without blocking, or block
      # while waiting for the next value. Capability ancestry alone creates no
      # entry in this table.
      record TraversalFacts,
        blocking : BlockingBehavior,
        consumption : ConsumptionBehavior,
        replayability : Replayability,
        finiteness : Finiteness,
        encounter_order : EncounterOrder

      # Inclusive bounds. Nil means analysis has no finite bound in that
      # direction; it does not mean the collection is infinite.
      record CardinalityBounds, minimum : Int64?, maximum : Int64? do
        def self.exact(value : Int64) : self
          new(value, value)
        end
      end

      record CollectionBlockBehavior,
        effects : Array(CollectionBlockEffect),
        may_raise : Bool,
        captured_mutation : Bool,
        abrupt_control_flow : Bool

      # Evidence for one bodyful semantic collection operation. These are laws
      # and graph observations only; no field is a fusion decision.
      record SemanticCollectionFacts,
        intermediate_escapes : Bool,
        block : CollectionBlockBehavior,
        encounter_order : EncounterOrder,
        replayability : Replayability,
        finiteness : Finiteness,
        input_cardinality : CardinalityBounds,
        output_cardinality : CardinalityBounds?

      record CallableSignature, name : String, parameter_types : Array(IR::Type), namespace_path : Array(String) = [] of String

      record NamespaceDefinition, path : Array(String), parent : Array(String)?
      record ConstantDefinition, declaration : NodeId, path : Array(String), type : IR::Type
      record TypeAliasDefinition, declaration : NodeId, path : Array(String), target : IR::Type

      alias CapabilityConformance = IR::CapabilityConformance

      # A resolved value-flow edge where one union is a strict member-subset of
      # the destination union. Analysis records only the type relation; planning
      # decides whether and how their representations convert.
      record UnionFlow, source : IR::Type, target : IR::Type

      # The concrete def selected for a call or constructor dispatch.
      # Downstream phases consume this edge instead of independently joining
      # calls and defs by name.
      record ResolvedCall, definition : NodeId, signature : CallableSignature do
        def name : String
          signature.name
        end
      end

      record StructLayout, fields : Array(IR::Field), reference : Bool

      record EnumMember, name : String, value : String
      record EnumDefinition, type : IR::Type, base_type : IR::Type, members : Array(EnumMember)

      # Resolved language inheritance for classes proven to descend from
      # Exception. The list is concrete-first and includes Exception itself;
      # planning can choose a runtime dispatch strategy without re-walking NIR.
      record ExceptionHierarchy, ancestors : Array(String)

      abstract struct Comparability
      end

      struct Comparable < Comparability
      end

      struct GoRejects < Comparability
        getter reason : String

        def initialize(@reason : String)
        end
      end

      struct WrongSemantics < Comparability
        getter reason : String

        def initialize(@reason : String)
        end
      end

      enum TypeRelation
        Exact
        Member
        Widening
        Impossible
      end

      record DispatchRelation, source : IR::Type, target : IR::Type, relation : TypeRelation

      # A node → declaration edge every navigation consumer (goto-definition,
      # hover) resolves through one uniform lookup. The variant names what the
      # node references; resolving each to a source location stays in the query
      # layer, which alone holds the NIR program.
      abstract struct Reference
      end

      # A `.new`, and the owning class an instance-var access belongs to.
      struct ClassReference < Reference
        getter name : String

        def initialize(@name : String)
        end
      end

      struct FieldReference < Reference
        getter owner : String
        getter field : String

        def initialize(@owner : String, @field : String)
        end
      end

      struct EnumMemberReference < Reference
        getter enum_type : IR::Type
        getter member : String

        def initialize(@enum_type : IR::Type, @member : String)
        end
      end

      struct ConstantReference < Reference
        getter declaration : NodeId
        getter path : Array(String)

        def initialize(@declaration : NodeId, @path : Array(String))
        end
      end

      struct TypeAliasReference < Reference
        getter declaration : NodeId
        getter path : Array(String)

        def initialize(@declaration : NodeId, @path : Array(String))
        end
      end

      # A local/param/block-arg/block-param read, resolved by lexical scope to
      # the NodeId of its binding declaration.
      struct LocalReference < Reference
        getter declaration : NodeId

        def initialize(@declaration : NodeId)
        end
      end

      # One source-level local introduced by an assignment. `References`
      # proves which of these bindings is read; lowering preserves an unused
      # assignment's value effects without creating a Go slot, while lint
      # turns the user-facing cases into advisory diagnostics.
      record LocalBinding, name : String

      # All type-analysis products travel as one cohesive fact group. Expression
      # typings are keyed by node; unions and arrays are the distinct concrete
      # types later representation strategies consume.
      class TypeFacts
        getter expressions = Hash(NodeId, IR::Type).new
        getter unions = Set(IR::Type).new
        getter arrays = Set(IR::Type).new
        getter hashes = Set(IR::Type).new
      end

      class Table
        getter types = TypeFacts.new
        getter go_externals = Hash(NodeId, Array(GoExternal)).new
        getter internal_calls = Hash(NodeId, ResolvedCall).new
        getter capability_conformances = Hash(NodeId, Array(CapabilityConformance)).new
        # Ordered instance-var layout for each class, keyed by class name:
        # each entry is (field name, field type).
        getter struct_layouts = Hash(String, StructLayout).new
        getter enums = Hash(IR::Type, EnumDefinition).new
        getter namespaces = Hash(NodeId, NamespaceDefinition).new
        getter namespace_owners = Hash(NodeId, Array(String)).new
        getter constants = Hash(Array(String), ConstantDefinition).new
        getter type_aliases = Hash(Array(String), TypeAliasDefinition).new
        getter exception_hierarchies = Hash(String, ExceptionHierarchy).new
        # Node → declaration edges (`.new`, instance-var access, local read),
        # produced by Passes::References. Concrete callable dispatch → def
        # edges live in internal_calls so planning and tooling consume the same
        # resolution.
        getter references = Hash(NodeId, Reference).new
        getter local_bindings = Hash(NodeId, LocalBinding).new
        # Assignment-target node → the local binding it writes. This includes
        # the binding's first assignment and later assignments to it.
        getter local_writes = Hash(NodeId, NodeId).new
        # Every lexical binding whose value is read, including params, block
        # args, rescue bindings, and select receive bindings. Consumers that
        # only need binding liveness query this set instead of walking NIR.
        getter binding_uses = Set(NodeId).new
        getter local_reads = Set(NodeId).new
        # Bindings whose values are never read. `_`-prefixed bindings remain
        # here so lowering avoids Go's unused-variable failure, but are omitted
        # from `unused_locals` because that spelling explicitly opts out of the
        # advisory lint.
        getter unread_local_writes = Set(NodeId).new
        getter unused_locals = Set(NodeId).new
        getter blocks = Hash(NodeId, BlockFacts).new
        getter comparabilities = Hash(IR::Type, Comparability).new
        getter dispatch_relations = Hash(NodeId, DispatchRelation).new
        getter union_flows = Hash(NodeId, UnionFlow).new
        getter external_types = Hash(IR::Type, IR::ExternalType).new
        getter scalar_stringifications = Hash(NodeId, ScalarStringification).new
        getter collection_uses = Hash(NodeId, Array(CollectionUse)).new
        getter semantic_collections = Hash(NodeId, SemanticCollectionFacts).new
        getter traversals = Hash(NodeId, TraversalFacts).new

        def binding_used?(declaration : NodeId) : Bool
          binding_uses.includes?(declaration)
        end
      end
    end
  end
end
