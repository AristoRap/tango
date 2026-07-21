require "./hierarchy_facts"

module Tango
  module Compiler
    module Editor
      # Immutable editor-facing projection of one analyzed program. Analysis owns
      # semantic truth; this index gives position-based tools one cohesive model
      # of source occurrences, declarations, and resolved references without
      # making each feature walk NIR or reinterpret compiler facts.
      class Index
        enum SymbolKind
          Class
          Struct
          Enum
          EnumMember
          Constant
          TypeAlias
          Function
          Method
          Constructor
          Field
          Local
          Parameter
          BlockArgument
          BlockParameter
        end

        record SymbolId, declaration : NodeId, kind : SymbolKind, member : String? = nil
        record Parameter, name : String, type : IR::Type
        record Signature,
          owner : IR::Type?,
          parameters : Array(Parameter),
          return_type : IR::Type?,
          kind : IR::NIR::CallableKind

        record Declaration,
          id : SymbolId,
          name : String,
          range : Source::Range,
          type : IR::Type? = nil,
          signature : Signature? = nil,
          documentation : String? = nil,
          visibility : Frontend::SyntaxSurface::Visibility = Frontend::SyntaxSurface::Visibility::Public do
          def kind : SymbolKind
            id.kind
          end
        end

        enum SymbolFamilyKind
          Single
          Callable
          Accessor
          Constructor
        end

        # One source-level rename unit. Crystal may emit several concrete defs
        # for one overload family, and generated accessors may expose getter,
        # setter, and field identities from one declaration token. Keeping that
        # relation explicit prevents mutation queries from joining by spelling.
        record SymbolFamily,
          kind : SymbolFamilyKind,
          name : String,
          domain : String,
          symbols : Array(SymbolId),
          declaration_ranges : Array(Source::Range)

        record Reference, range : Source::Range, node : NodeId, declaration : SymbolId?
        enum ReceiverKind
          Instance
          Class
        end

        record Receiver, type : IR::Type, kind : ReceiverKind

        enum OccurrenceKind
          Identifier
          Expression

          def priority : Int32
            identifier? ? 0 : 1
          end
        end

        record Occurrence, range : Source::Range, node : NodeId, kind : OccurrenceKind

        # Query-shaped semantic data is retained independently from NIR so a
        # background analysis can cross a process boundary without making
        # request handlers deserialize or walk compiler structures.
        record CallableSite,
          owner : IR::Type,
          name : String,
          argument_types : Array(IR::Type),
          return_type : IR::Type,
          name_span : Source::Range?,
          kind : IR::NIR::CallableKind
        record SemanticNode,
          node : NodeId,
          type : IR::Type? = nil,
          method_site : CallableSite? = nil
        record ReceiverOccurrence,
          range : Source::Range,
          receiver : Receiver,
          kind : OccurrenceKind = OccurrenceKind::Expression

        enum InlayHintKind
          Type
          Parameter
        end

        record InlayHint,
          anchor : Source::Range,
          label : String,
          kind : InlayHintKind

        enum SemanticTokenKind
          Class
          Function
          Method
          Variable
          Parameter
          Property
        end

        record SemanticToken,
          range : Source::Range,
          kind : SemanticTokenKind,
          declaration : Bool = false,
          modification : Bool = false

        getter declarations = [] of Declaration
        getter references = [] of Reference
        getter occurrences = [] of Occurrence
        getter semantic_nodes = [] of SemanticNode
        getter receiver_occurrences = [] of ReceiverOccurrence
        getter inlay_hints = [] of InlayHint
        getter semantic_tokens = [] of SemanticToken
        getter hierarchy = HierarchyFacts.new
        getter captured_symbols = Set(SymbolId).new
        getter symbol_families = [] of SymbolFamily
        @nodes = Hash(NodeId, IR::NIR::Stmt).new
        @semantic_by_node = Hash(NodeId, SemanticNode).new
        @declarations_by_id = Hash(SymbolId, Declaration).new
        @symbols_by_node = Hash(NodeId, SymbolId).new
        @classes_by_name = Hash(String, SymbolId).new
        @enums_by_type = Hash(IR::Type, SymbolId).new
        @families_by_symbol = Hash(SymbolId, SymbolFamily).new
        @block_arg_types = Hash(NodeId, IR::Type).new
        @syntax_surface = Frontend::SyntaxSurface::Index.new

        def self.from(
          nir : IR::NIR::Program?,
          facts : Analysis::Facts::Table?,
          syntax_surface : Frontend::SyntaxSurface::Index = Frontend::SyntaxSurface::Index.new,
        ) : self
          index = new
          index.use_syntax_surface(syntax_surface)
          index.add_program(nir, facts) if nir
          index
        end

        def self.projected(
          declarations : Array(Declaration),
          references : Array(Reference),
          occurrences : Array(Occurrence),
          semantic_nodes : Array(SemanticNode),
          receiver_occurrences : Array(ReceiverOccurrence),
          inlay_hints : Array(InlayHint),
          semantic_tokens : Array(SemanticToken),
          captured_symbols : Set(SymbolId),
          syntax_surface : Frontend::SyntaxSurface::Index,
        ) : self
          index = new
          index.import_projection(
            declarations,
            references,
            occurrences,
            semantic_nodes,
            receiver_occurrences,
            inlay_hints,
            semantic_tokens,
            captured_symbols,
            syntax_surface
          )
          index
        end

        def import_projection(
          declarations : Array(Declaration),
          references : Array(Reference),
          occurrences : Array(Occurrence),
          semantic_nodes : Array(SemanticNode),
          receiver_occurrences : Array(ReceiverOccurrence),
          inlay_hints : Array(InlayHint),
          semantic_tokens : Array(SemanticToken),
          captured_symbols : Set(SymbolId),
          syntax_surface : Frontend::SyntaxSurface::Index,
        ) : Nil
          use_syntax_surface(syntax_surface)
          declarations.each { |declaration| import_declaration(declaration) }
          references.each { |reference| @references << reference }
          occurrences.each { |occurrence| @occurrences << occurrence }
          semantic_nodes.each { |semantic| import_semantic_node(semantic) }
          receiver_occurrences.each { |receiver| @receiver_occurrences << receiver }
          inlay_hints.each { |hint| @inlay_hints << hint }
          semantic_tokens.each { |token| @semantic_tokens << token }
          captured_symbols.each { |symbol| @captured_symbols << symbol }
          build_symbol_families
        end

        def use_syntax_surface(surface : Frontend::SyntaxSurface::Index) : Nil
          @syntax_surface = surface
        end

        def add_program(program : IR::NIR::Program, facts : Analysis::Facts::Table?) : Nil
          collect_block_arg_types(program)
          IR::NIR::Walk.children(program).each { |stmt| add_stmt(stmt, facts) }
          add_resolutions(facts) if facts
          build_inlay_hints if facts
          build_semantic_tokens(facts) if facts
          build_hierarchy(program, facts)
          build_symbol_families
        end

        def import_hierarchy(@hierarchy : HierarchyFacts) : Nil
        end

        def semantic_node(id : NodeId) : SemanticNode?
          @semantic_by_node[id]?
        end

        def captured?(id : SymbolId) : Bool
          @captured_symbols.includes?(id)
        end

        def declaration(id : SymbolId) : Declaration?
          @declarations_by_id[id]?
        end

        def symbol_family(id : SymbolId) : SymbolFamily?
          @families_by_symbol[id]?
        end

        def class_declaration(type : IR::Type) : Declaration?
          return nil unless type.family.class?
          name = type.name
          return nil unless name
          source_name = name.ends_with?(".class") ? name.rchop(".class") : name
          @classes_by_name[source_name]?.try { |id| declaration(id) }
        end

        def rename_collision?(family : SymbolFamily, new_name : String) : Bool
          semantic = @symbol_families.any? do |candidate|
            candidate.domain == family.domain &&
              candidate.name == new_name &&
              candidate.symbols.none? { |symbol| family.symbols.includes?(symbol) }
          end
          return true if semantic

          if family.domain == "callable:global"
            @syntax_surface.declarations.any? { |declaration| declaration.kind.function? && declaration.name == new_name }
          elsif family.domain.starts_with?("member:")
            owner = family.domain.lchop("member:")
            @syntax_surface.declarations.any? do |declaration|
              declaration.container == owner && declaration.name.rchop('=') == new_name &&
                (declaration.kind.method? || declaration.kind.field? || (declaration.kind.local? && declaration.scope_id.nil?))
            end
          elsif family.domain == "type:global"
            @syntax_surface.declarations.any? do |declaration|
              (declaration.kind.class? || declaration.kind.struct? || declaration.kind.module?) && declaration.name == new_name
            end
          else
            false
          end
        end

        def declaration_at(path : String, offset : Int32) : Declaration?
          @declarations
            .select { |decl| decl.range.contains?(path, offset) }
            .min_by?(&.range.length)
        end

        def reference_at(path : String, offset : Int32) : Reference?
          @references
            .select { |reference| reference.range.contains?(path, offset) }
            .min_by? { |reference| {reference.range.length, reference.declaration ? 0 : 1} }
        end

        def symbol_at(path : String, offset : Int32) : SymbolId?
          declaration_at(path, offset).try(&.id) || reference_at(path, offset).try(&.declaration)
        end

        def occurrences(symbol : SymbolId, include_declaration : Bool = true) : Array(Source::Range)
          ranges = @references.select(&.declaration.==(symbol)).map(&.range)
          if include_declaration
            declaration(symbol).try { |declaration| ranges << declaration.range }
          end
          ranges.sort_by { |range| {range.path, range.start_offset, range.end_offset} }
        end

        def receiver_at(path : String, offset : Int32) : Receiver?
          @receiver_occurrences
            .select { |entry| entry.range.contains?(path, offset) }
            .min_by? { |entry| {entry.kind.priority, entry.range.length} }
            .try(&.receiver)
        end

        private def add_stmt(stmt : IR::NIR::Stmt, facts : Analysis::Facts::Table?) : Nil
          @nodes[stmt.id] = stmt
          stmt.span.try { |range| add_occurrence(range, stmt.id, OccurrenceKind::Expression) }
          identifier_ranges(stmt).each { |range| add_occurrence(range, stmt.id, OccurrenceKind::Identifier) }

          if expr = stmt.as?(IR::NIR::Expr)
            site = expr.method_site.try { |method_site| callable_site(method_site) }
            import_semantic_node(SemanticNode.new(expr.id, expr.type, site))
            if receiver = receiver_for(expr)
              expr.span.try do |range|
                @receiver_occurrences << ReceiverOccurrence.new(range, receiver, OccurrenceKind::Expression)
              end
              identifier_ranges(expr).each do |range|
                @receiver_occurrences << ReceiverOccurrence.new(range, receiver, OccurrenceKind::Identifier)
              end
            end
          end

          case stmt
          when IR::NIR::Class
            add_class(stmt)
          when IR::NIR::Enum
            add_enum(stmt)
          when IR::NIR::Constant
            add_constant(stmt)
          when IR::NIR::TypeAlias
            add_type_alias(stmt)
          when IR::NIR::Def
            add_def(stmt, facts)
            return
          when IR::NIR::Param
            if range = declaration_range(stmt)
              add_binding(stmt.id, stmt.name, SymbolKind::Parameter, stmt.type, range)
            end
          when IR::NIR::BlockArg
            if range = declaration_range(stmt)
              add_binding(stmt.id, stmt.name, SymbolKind::BlockArgument, @block_arg_types[stmt.id]?, range)
            end
          when IR::NIR::BlockParam
            add_block_param(stmt)
          when IR::NIR::Local
            reference = facts.try { |table| table.references[stmt.id]? }
            unless reference.is_a?(Analysis::Facts::LocalReference)
              if range = source_name_range(stmt)
                # SourceLocations has verified that this range contains the
                # actual name. Crystal-generated `__temp_*` locals point into
                # expressions instead and therefore have no editor identity.
                add_binding(stmt.id, stmt.name, SymbolKind::Local, stmt.type, range)
              end
            end
          end

          add_children(stmt, facts)
        end

        private def build_symbol_families : Nil
          @symbol_families.clear
          @families_by_symbol.clear
          groups = Hash(String, Array(Declaration)).new { |hash, key| hash[key] = [] of Declaration }
          @declarations.each { |declaration| groups[family_key(declaration)] << declaration }

          groups.each_value do |members|
            first = members.first
            name = rename_name(first)
            kind = family_kind(members)
            ranges = members.compact_map do |declaration|
              surface = @syntax_surface.declaration_at(declaration.range)
              declaration.range if surface && rename_name(declaration) == surface.name
            end
            ranges.concat(uninstantiated_family_ranges(first, name))
            ranges = ranges.uniq.sort_by { |range| {range.path, range.start_offset, range.end_offset} }
            symbols = members.map(&.id).uniq.sort_by { |id| {id.declaration.value, id.kind.to_s, id.member.to_s} }
            family = SymbolFamily.new(kind, name, collision_domain(first), symbols, ranges)
            @symbol_families << family
            symbols.each { |symbol| @families_by_symbol[symbol] = family }
          end
          @symbol_families.sort_by! { |family| {family.domain, family.name, family.kind.to_s} }
        end

        private def family_key(declaration : Declaration) : String
          name = rename_name(declaration)
          case declaration.kind
          when .function?
            "callable\u0000global\u0000#{name}"
          when .method?
            signature = declaration.signature
            owner = signature.try(&.owner).try(&.to_s).to_s
            if signature.try(&.kind.initializer?)
              "constructor\u0000#{owner}"
            else
              "member\u0000#{owner}\u0000#{name}"
            end
          when .field?
            "member\u0000#{field_owner(declaration)}\u0000#{name}"
          else
            "single\u0000#{declaration.id.declaration.value}\u0000#{declaration.id.kind}\u0000#{declaration.id.member}"
          end
        end

        private def family_kind(declarations : Array(Declaration)) : SymbolFamilyKind
          return SymbolFamilyKind::Constructor if declarations.any? { |declaration| declaration.signature.try(&.kind.initializer?) }
          return SymbolFamilyKind::Accessor if declarations.any?(&.kind.field?)
          return SymbolFamilyKind::Callable if declarations.any? { |declaration| declaration.kind.function? || declaration.kind.method? }
          SymbolFamilyKind::Single
        end

        private def uninstantiated_family_ranges(declaration : Declaration, name : String) : Array(Source::Range)
          case declaration.kind
          when .function?
            @syntax_surface.declarations.compact_map do |surface|
              surface.selection_range if surface.kind.function? && surface.name == name
            end
          when .method?
            signature = declaration.signature
            return [] of Source::Range unless signature && !signature.kind.initializer?
            owner = signature.owner.try(&.name) || signature.owner.try(&.to_s)
            @syntax_surface.declarations.compact_map do |surface|
              next unless surface.kind.method? && surface.name == name && surface.container == owner
              next unless callable_kinds_match?(surface.callable_kind, signature.kind)
              surface.selection_range
            end
          else
            [] of Source::Range
          end
        end

        private def callable_kinds_match?(
          surface : Frontend::SyntaxSurface::CallableKind?,
          semantic : IR::NIR::CallableKind,
        ) : Bool
          return false unless surface
          (surface.function? && semantic.function?) ||
            (surface.instance_method? && semantic.instance_method?) ||
            (surface.class_method? && semantic.class_method?) ||
            (surface.initializer? && semantic.initializer?)
        end

        private def collision_domain(declaration : Declaration) : String
          case declaration.kind
          when .function?
            "callable:global"
          when .method?
            "member:#{declaration.signature.try(&.owner).try(&.to_s)}"
          when .field?
            "member:#{field_owner(declaration)}"
          when .class?, .struct?
            "type:global"
          else
            "lexical:#{declaration.range.path}:#{lexical_scope(declaration)}"
          end
        end

        private def lexical_scope(declaration : Declaration) : String
          surface = @syntax_surface.declaration_at(declaration.range)
          if scope = surface.try(&.scope_id)
            return scope
          end
          @syntax_surface.scopes
            .select { |scope| scope.kind.callable? && scope.range.contains?(declaration.range.path, declaration.range.start_offset) }
            .min_by?(&.range.length)
            .try(&.id) || "top-level"
        end

        private def field_owner(declaration : Declaration) : String
          @declarations.find do |candidate|
            (candidate.kind.class? || candidate.kind.struct?) && candidate.id.declaration == declaration.id.declaration
          end.try(&.name).to_s
        end

        private def rename_name(declaration : Declaration) : String
          declaration.name.ends_with?('=') ? declaration.name.rchop('=') : declaration.name
        end

        private def add_def(stmt : IR::NIR::Def, facts : Analysis::Facts::Table?) : Nil
          if range = declaration_range(stmt)
            id = SymbolId.new(stmt.id, symbol_kind(stmt.callable_kind))
            params = stmt.owner ? stmt.params.reject { |param| param.name == "self" } : stmt.params
            add_declaration(
              Declaration.new(
                id,
                stmt.name,
                range,
                signature: Signature.new(
                  stmt.owner,
                  params.map { |param| Parameter.new(param.name, param.type || IR::Type.unknown) },
                  stmt.return_type,
                  stmt.callable_kind
                )
              )
            )
          end
          add_children(stmt, facts)
        end

        private def add_block_param(stmt : IR::NIR::BlockParam) : Nil
          range = declaration_range(stmt)
          return unless range
          id = SymbolId.new(stmt.id, SymbolKind::BlockParameter)
          add_declaration(
            Declaration.new(
              id,
              stmt.name,
              range,
              signature: Signature.new(
                nil,
                stmt.signature.param_types.map_with_index { |type, index| Parameter.new("arg#{index + 1}", type) },
                stmt.signature.return_type,
                IR::NIR::CallableKind::Proc
              )
            )
          )
        end

        private def add_binding(id : NodeId, name : String, kind : SymbolKind, type : IR::Type?, range : Source::Range) : Nil
          add_declaration(Declaration.new(SymbolId.new(id, kind), name, range, type))
        end

        private def add_declaration(declaration : Declaration) : Nil
          if surface = @syntax_surface.declaration_at(declaration.range)
            declaration = declaration.copy_with(
              documentation: surface.documentation,
              visibility: surface.visibility
            )
          end
          import_declaration(declaration)
        end

        private def import_declaration(declaration : Declaration) : Nil
          @declarations << declaration
          @declarations_by_id[declaration.id] = declaration
          @symbols_by_node[declaration.id.declaration] = declaration.id unless declaration.id.member
          @classes_by_name[declaration.name] = declaration.id if declaration.kind.class? || declaration.kind.struct?
        end

        private def import_semantic_node(semantic : SemanticNode) : Nil
          @semantic_nodes << semantic
          @semantic_by_node[semantic.node] = semantic
        end

        private def add_resolutions(facts : Analysis::Facts::Table) : Nil
          facts.references.each do |node_id, reference|
            target =
              case reference
              when Analysis::Facts::LocalReference
                @symbols_by_node[reference.declaration]?
              when Analysis::Facts::ClassReference
                @classes_by_name[reference.name]?
              when Analysis::Facts::FieldReference
                @classes_by_name[reference.owner]?.try do |owner|
                  SymbolId.new(owner.declaration, SymbolKind::Field, reference.field)
                end
              when Analysis::Facts::EnumMemberReference
                @enums_by_type[reference.enum_type]?.try do |owner|
                  SymbolId.new(owner.declaration, SymbolKind::EnumMember, reference.member)
                end
              when Analysis::Facts::ConstantReference
                @symbols_by_node[reference.declaration]?
              when Analysis::Facts::TypeAliasReference
                @symbols_by_node[reference.declaration]?
              end
            node = @nodes[node_id]?
            add_reference(node_id, target, source_name_range(node) || node.try(&.span))
          end

          facts.internal_calls.each do |node_id, resolved|
            node = @nodes[node_id]?
            add_reference(node_id, @symbols_by_node[resolved.definition]?, method_range(node) || source_name_range(node))
            add_parameter_hints(node, @nodes[resolved.definition]?.as?(IR::NIR::Def))
          end

          # A source node can carry more than one semantic occurrence. `Point.new`
          # has a class reference on `Point` and a constructor reference on `new`.
          # Specialized receiver calls may have no declaration in this snapshot;
          # their MethodSite still supplies a structured hover signature. A nil
          # target is deliberate: navigation never reconstructs callable identity
          # from owner/name/kind after analysis has resolved concrete dispatches.
          @nodes.each_value do |node|
            next unless node.is_a?(IR::NIR::Expr) && (site = node.method_site)
            range = site.name_span
            next unless range
            next if @references.any? { |reference| reference.node == node.id && reference.range == range }

            add_reference(node.id, nil, range)
          end

          facts.blocks.each_value do |block|
            next unless block.escapes
            block.captured.each do |capture|
              if symbol = @symbols_by_node[capture.declaration]?
                @captured_symbols << symbol
              end
            end
          end
        end

        private def build_inlay_hints : Nil
          @declarations.each do |declaration|
            next unless declaration.kind.local?
            type = declaration.type
            next unless type && !type.family.unknown?
            surface = local_surface_declaration(declaration)
            next unless surface
            next if surface.explicit_type

            @inlay_hints << InlayHint.new(
              surface.selection_range,
              ": #{type.to_semantic_s}",
              InlayHintKind::Type
            )
          end

          @inlay_hints.sort_by! do |hint|
            {hint.anchor.path, hint.anchor.start_offset, hint.kind.to_s, hint.label}
          end
        end

        private def add_parameter_hints(node : IR::NIR::Stmt?, definition : IR::NIR::Def?) : Nil
          return unless node && definition
          parameters = definition.owner ? definition.params.reject { |parameter| parameter.name == "self" } : definition.params
          # A selected compiler-generated specialization can have callable and
          # parameter names but no Tango declaration ranges (`Range#initialize`
          # exposes `__arg0`, `__arg1`, and `exclusive`). Those names are
          # implementation details, not editor labels. Require the complete
          # selected signature to be source-authored before positional mapping.
          return unless definition.name_span && parameters.all?(&.name_span)
          arguments = source_arguments(node, parameters.size)

          arguments.zip(parameters).each do |argument, parameter|
            range = argument.span
            next unless range
            next if argument_name(argument) == parameter.name
            @inlay_hints << InlayHint.new(
              range,
              "#{parameter.name}:",
              InlayHintKind::Parameter
            )
          end
        end

        private def source_arguments(node : IR::NIR::Stmt, count : Int32) : Array(IR::NIR::Expr)
          arguments = case node
                      when IR::NIR::Call        then node.args
                      when IR::NIR::New         then node.args
                      when IR::NIR::InvokeBlock then node.args
                      else                           [] of IR::NIR::Expr
                      end
          return [] of IR::NIR::Expr if count.zero?
          arguments.last(count)
        end

        # Crystal can reuse a typed local's semantic Var object at a later read,
        # so that NIR declaration identity remains exact while its source range
        # no longer lands on the TypeDeclaration token. The fallback joins that
        # semantic identity to the parser-owned declaration within the same
        # lexical scope. It is used only to observe an explicit annotation;
        # the hint type still comes exclusively from semantic analysis.
        private def local_surface_declaration(declaration : Declaration) : Frontend::SyntaxSurface::Declaration?
          if surface = @syntax_surface.declaration_at(declaration.range)
            return surface
          end

          scope_id = @syntax_surface.scopes
            .select { |scope| scope.kind.callable? && scope.range.contains?(declaration.range.path, declaration.range.start_offset) }
            .min_by?(&.range.length)
            .try(&.id)
          @syntax_surface.declarations
            .select do |surface|
              selection = surface.selection_range
              surface.kind.local? &&
                surface.name == declaration.name &&
                surface.scope_id == scope_id &&
                selection.path == declaration.range.path &&
                selection.start_offset <= declaration.range.start_offset
            end
            .max_by?(&.selection_range.start_offset)
        end

        private def argument_name(argument : IR::NIR::Expr) : String?
          case argument
          when IR::NIR::Local       then argument.name
          when IR::NIR::InstanceVar then argument.name.lchop('@')
          end
        end

        private def add_reference(node_id : NodeId, declaration : SymbolId?, range : Source::Range?) : Nil
          return unless range
          @references << Reference.new(range, node_id, declaration)
        end

        private def add_occurrence(range : Source::Range, node : NodeId, kind : OccurrenceKind) : Nil
          return if @occurrences.any? { |entry| entry.node == node && entry.range == range && entry.kind == kind }
          @occurrences << Occurrence.new(range, node, kind)
        end

        private def identifier_ranges(stmt : IR::NIR::Stmt) : Array(Source::Range)
          ranges = [] of Source::Range
          source_name_range(stmt).try { |range| ranges << range }
          method_range(stmt).try { |range| ranges << range unless ranges.includes?(range) }
          ranges
        end

        private def source_name_range(stmt : IR::NIR::Stmt?) : Source::Range?
          return nil unless stmt
          stmt.name_span if stmt.responds_to?(:name_span)
        end

        private def method_range(stmt : IR::NIR::Stmt?) : Source::Range?
          return nil unless stmt.is_a?(IR::NIR::Expr)
          stmt.method_site.try(&.name_span)
        end

        private def declaration_range(stmt : IR::NIR::Stmt) : Source::Range?
          source_name_range(stmt) || stmt.span
        end

        private def symbol_kind(kind : IR::NIR::CallableKind) : SymbolKind
          case kind
          in .function?                                       then SymbolKind::Function
          in .constructor?                                    then SymbolKind::Constructor
          in .instance_method?, .class_method?, .initializer? then SymbolKind::Method
          in .proc?                                           then SymbolKind::Function
          end
        end

        private def add_children(stmt : IR::NIR::Stmt, facts : Analysis::Facts::Table?) : Nil
          IR::NIR::Walk.children(stmt).each { |child| add_stmt(child, facts) }
        end

        private def collect_block_arg_types(program : IR::NIR::Program) : Nil
          IR::NIR::Walk.children(program).each { |stmt| collect_block_arg_types(stmt) }
        end

        private def collect_block_arg_types(stmt : IR::NIR::Stmt) : Nil
          if stmt.is_a?(IR::NIR::BlockLiteral)
            stmt.args.each_with_index do |arg, index|
              if type = stmt.signature.param_types[index]?
                @block_arg_types[arg.id] = type
              end
            end
          end
          IR::NIR::Walk.children(stmt).each { |child| collect_block_arg_types(child) }
        end

        private def metaclass_owner(type : IR::Type) : IR::Type?
          return unless type.family.class?
          name = type.name
          return unless name && name.ends_with?(".class")

          IR::Type.klass(name.rchop(".class"), type.type_args)
        end

        private def receiver_for(node : IR::NIR::Expr) : Receiver?
          type = node.type
          return unless type && !type.family.unknown?
          return Receiver.new(type, ReceiverKind::Class) if node.is_a?(IR::NIR::ClassRef) || node.is_a?(IR::NIR::New)

          # A standalone semantic path (`File`) currently crosses NIR as an
          # unsupported value whose Crystal-resolved type is `File.class`.
          if owner = metaclass_owner(type)
            return Receiver.new(owner, ReceiverKind::Class)
          end

          Receiver.new(type, ReceiverKind::Instance)
        end

        private def callable_site(site : IR::NIR::MethodSite) : CallableSite
          CallableSite.new(
            site.owner,
            site.name,
            site.argument_types,
            site.return_type,
            site.name_span,
            site.kind
          )
        end
      end
    end
  end
end
