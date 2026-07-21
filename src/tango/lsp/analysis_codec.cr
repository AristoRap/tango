require "json"
require "../transport"

module Tango
  module Lsp
    # JSON transport for the immutable editor projection produced in an
    # isolated analysis process. This deliberately excludes Crystal semantic
    # objects, NIR, Facts, Plans, and LIR; requests consume only the source,
    # diagnostics, syntax catalog, and semantic editor index they need.
    module AnalysisCodec
      alias RangeData = Transport::RangeData
      alias TypeData = Transport::TypeData
      alias SurfaceParameterData = Transport::SurfaceParameterData
      alias SurfaceDeclarationData = Transport::SurfaceDeclarationData
      alias SurfaceScopeData = Transport::SurfaceScopeData
      alias DiagnosticData = Transport::DiagnosticData
      alias RelatedDiagnosticData = Transport::RelatedDiagnosticData
      alias DiagnosticFixEditData = Transport::DiagnosticFixEditData
      alias DiagnosticFixData = Transport::DiagnosticFixData
      alias FileData = Transport::FileData
      alias RequireData = Transport::RequireData
      alias EdgeData = Transport::EdgeData

      class SymbolData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter declaration : String
        getter kind : String
        getter member : String?

        def initialize(symbol : Compiler::Editor::Index::SymbolId)
          @declaration = symbol.declaration.value
          @kind = symbol.kind.to_s
          @member = symbol.member
        end

        def to_symbol : Compiler::Editor::Index::SymbolId
          Compiler::Editor::Index::SymbolId.new(
            NodeId.new(@declaration),
            Compiler::Editor::Index::SymbolKind.parse(@kind),
            @member
          )
        end
      end

      class MethodSiteData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter owner : TypeData
        getter name : String
        getter argument_types : Array(TypeData)
        getter return_type : TypeData
        getter name_span : RangeData?
        getter kind : String

        def initialize(site : Compiler::Editor::Index::CallableSite)
          @owner = TypeData.new(site.owner)
          @name = site.name
          @argument_types = site.argument_types.map { |type| TypeData.new(type) }
          @return_type = TypeData.new(site.return_type)
          @name_span = site.name_span.try { |range| RangeData.new(range) }
          @kind = site.kind.to_s
        end

        def to_method_site : Compiler::Editor::Index::CallableSite
          Compiler::Editor::Index::CallableSite.new(
            @owner.to_type,
            @name,
            @argument_types.map(&.to_type),
            @return_type.to_type,
            @name_span.try(&.to_range),
            IR::NIR::CallableKind.parse(@kind)
          )
        end
      end

      class IndexParameterData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter name : String
        getter type : TypeData

        def initialize(parameter : Compiler::Editor::Index::Parameter)
          @name = parameter.name
          @type = TypeData.new(parameter.type)
        end

        def to_parameter : Compiler::Editor::Index::Parameter
          Compiler::Editor::Index::Parameter.new(@name, @type.to_type)
        end
      end

      class SignatureData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter owner : TypeData?
        getter parameters : Array(IndexParameterData)
        getter return_type : TypeData?
        getter kind : String

        def initialize(signature : Compiler::Editor::Index::Signature)
          @owner = signature.owner.try { |type| TypeData.new(type) }
          @parameters = signature.parameters.map { |parameter| IndexParameterData.new(parameter) }
          @return_type = signature.return_type.try { |type| TypeData.new(type) }
          @kind = signature.kind.to_s
        end

        def to_signature : Compiler::Editor::Index::Signature
          Compiler::Editor::Index::Signature.new(
            @owner.try(&.to_type),
            @parameters.map(&.to_parameter),
            @return_type.try(&.to_type),
            IR::NIR::CallableKind.parse(@kind)
          )
        end
      end

      class DeclarationData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter id : SymbolData
        getter name : String
        getter range : RangeData
        getter type : TypeData?
        getter signature : SignatureData?
        getter documentation : String?
        getter visibility : String

        def initialize(declaration : Compiler::Editor::Index::Declaration)
          @id = SymbolData.new(declaration.id)
          @name = declaration.name
          @range = RangeData.new(declaration.range)
          @type = declaration.type.try { |type| TypeData.new(type) }
          @signature = declaration.signature.try { |signature| SignatureData.new(signature) }
          @documentation = declaration.documentation
          @visibility = declaration.visibility.to_s
        end

        def to_declaration : Compiler::Editor::Index::Declaration
          Compiler::Editor::Index::Declaration.new(
            @id.to_symbol,
            @name,
            @range.to_range,
            @type.try(&.to_type),
            @signature.try(&.to_signature),
            @documentation,
            Frontend::SyntaxSurface::Visibility.parse(@visibility)
          )
        end
      end

      class ReferenceData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter range : RangeData
        getter node : String
        getter declaration : SymbolData?

        def initialize(reference : Compiler::Editor::Index::Reference)
          @range = RangeData.new(reference.range)
          @node = reference.node.value
          @declaration = reference.declaration.try { |symbol| SymbolData.new(symbol) }
        end

        def to_reference : Compiler::Editor::Index::Reference
          Compiler::Editor::Index::Reference.new(
            @range.to_range,
            NodeId.new(@node),
            @declaration.try(&.to_symbol)
          )
        end
      end

      class OccurrenceData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter range : RangeData
        getter node : String
        getter kind : String

        def initialize(occurrence : Compiler::Editor::Index::Occurrence)
          @range = RangeData.new(occurrence.range)
          @node = occurrence.node.value
          @kind = occurrence.kind.to_s
        end

        def to_occurrence : Compiler::Editor::Index::Occurrence
          Compiler::Editor::Index::Occurrence.new(
            @range.to_range,
            NodeId.new(@node),
            Compiler::Editor::Index::OccurrenceKind.parse(@kind)
          )
        end
      end

      class SemanticNodeData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter node : String
        getter type : TypeData?
        getter method_site : MethodSiteData?

        def initialize(semantic : Compiler::Editor::Index::SemanticNode)
          @node = semantic.node.value
          @type = semantic.type.try { |type| TypeData.new(type) }
          @method_site = semantic.method_site.try { |site| MethodSiteData.new(site) }
        end

        def to_semantic_node : Compiler::Editor::Index::SemanticNode
          Compiler::Editor::Index::SemanticNode.new(
            NodeId.new(@node),
            @type.try(&.to_type),
            @method_site.try(&.to_method_site)
          )
        end
      end

      class ReceiverOccurrenceData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter range : RangeData
        getter type : TypeData
        getter receiver_kind : String
        getter occurrence_kind : String

        def initialize(occurrence : Compiler::Editor::Index::ReceiverOccurrence)
          @range = RangeData.new(occurrence.range)
          @type = TypeData.new(occurrence.receiver.type)
          @receiver_kind = occurrence.receiver.kind.to_s
          @occurrence_kind = occurrence.kind.to_s
        end

        def to_receiver_occurrence : Compiler::Editor::Index::ReceiverOccurrence
          receiver = Compiler::Editor::Index::Receiver.new(
            @type.to_type,
            Compiler::Editor::Index::ReceiverKind.parse(@receiver_kind)
          )
          Compiler::Editor::Index::ReceiverOccurrence.new(
            @range.to_range,
            receiver,
            Compiler::Editor::Index::OccurrenceKind.parse(@occurrence_kind)
          )
        end
      end

      class InlayHintData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter anchor : RangeData
        getter label : String
        getter kind : String

        def initialize(hint : Compiler::Editor::Index::InlayHint)
          @anchor = RangeData.new(hint.anchor)
          @label = hint.label
          @kind = hint.kind.to_s
        end

        def to_inlay_hint : Compiler::Editor::Index::InlayHint
          Compiler::Editor::Index::InlayHint.new(
            @anchor.to_range,
            @label,
            Compiler::Editor::Index::InlayHintKind.parse(@kind)
          )
        end
      end

      class SemanticTokenData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter range : RangeData
        getter kind : String
        getter declaration : Bool
        getter modification : Bool

        def initialize(token : Compiler::Editor::Index::SemanticToken)
          @range = RangeData.new(token.range)
          @kind = token.kind.to_s
          @declaration = token.declaration
          @modification = token.modification
        end

        def to_semantic_token : Compiler::Editor::Index::SemanticToken
          Compiler::Editor::Index::SemanticToken.new(
            @range.to_range,
            Compiler::Editor::Index::SemanticTokenKind.parse(@kind),
            @declaration,
            @modification
          )
        end
      end

      # The same structured key is used by the analysis-process codec and LSP
      # item `data`, so follow-up requests never recover identity from a label.
      class HierarchyKeyData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter type : TypeData
        getter declaration : RangeData

        def initialize(key : Compiler::Editor::Index::HierarchyFacts::Key)
          @type = TypeData.new(key.type)
          @declaration = RangeData.new(key.declaration)
        end

        def to_key : Compiler::Editor::Index::HierarchyFacts::Key
          Compiler::Editor::Index::HierarchyFacts::Key.new(@type.to_type, @declaration.to_range)
        end
      end

      class HierarchyItemData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter key : HierarchyKeyData
        getter item_kind : String
        getter declaration_range : RangeData

        def initialize(item : Compiler::Editor::Index::HierarchyFacts::Item)
          @key = HierarchyKeyData.new(item.key)
          @item_kind = item.kind.to_s
          @declaration_range = RangeData.new(item.range)
        end

        def to_item : Compiler::Editor::Index::HierarchyFacts::Item
          key = @key.to_key
          Compiler::Editor::Index::HierarchyFacts::Item.new(
            key,
            key.type.to_semantic_s,
            Compiler::Editor::Index::HierarchyFacts::ItemKind.parse(@item_kind),
            @declaration_range.to_range,
            key.declaration
          )
        end
      end

      class HierarchyRelationData
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter subtype : HierarchyKeyData
        getter supertype : HierarchyKeyData
        getter kind : String
        getter completeness : String

        def initialize(relation : Compiler::Editor::Index::HierarchyFacts::Relation)
          @subtype = HierarchyKeyData.new(relation.subtype)
          @supertype = HierarchyKeyData.new(relation.supertype)
          @kind = relation.kind.to_s
          @completeness = relation.completeness.to_s
        end

        def to_relation : Compiler::Editor::Index::HierarchyFacts::Relation
          Compiler::Editor::Index::HierarchyFacts::Relation.new(
            @subtype.to_key,
            @supertype.to_key,
            Compiler::Editor::Index::HierarchyFacts::RelationKind.parse(@kind),
            Compiler::Editor::Index::HierarchyFacts::Completeness.parse(@completeness)
          )
        end
      end

      class Payload
        include JSON::Serializable
        include JSON::Serializable::Strict
        getter entrypoint : String
        getter files : Array(FileData)
        getter requires : Array(RequireData)
        getter edges : Array(EdgeData)
        getter diagnostics : Array(DiagnosticData)
        getter declarations : Array(DeclarationData)
        getter references : Array(ReferenceData)
        getter occurrences : Array(OccurrenceData)
        getter semantic_nodes : Array(SemanticNodeData)
        getter receiver_occurrences : Array(ReceiverOccurrenceData)
        getter inlay_hints : Array(InlayHintData)
        getter semantic_tokens : Array(SemanticTokenData)
        getter hierarchy_items : Array(HierarchyItemData)
        getter hierarchy_relations : Array(HierarchyRelationData)
        getter captured_symbols : Array(SymbolData)
        getter surface_declarations : Array(SurfaceDeclarationData)
        getter surface_scopes : Array(SurfaceScopeData)
        getter semantic_ready : Bool

        def initialize(snapshot : Compiler::Snapshot)
          @entrypoint = snapshot.source.entrypoint.path
          @files = snapshot.source.files.map { |file| FileData.new(file) }
          @requires = snapshot.source.requires.map { |directive| RequireData.new(directive) }
          @edges = snapshot.source.edges.map { |edge| EdgeData.new(edge) }
          @diagnostics = snapshot.diagnostics.map { |diagnostic| DiagnosticData.new(diagnostic) }
          index = snapshot.editor_index
          @declarations = index.declarations.map { |declaration| DeclarationData.new(declaration) }
          @references = index.references.map { |reference| ReferenceData.new(reference) }
          @occurrences = index.occurrences.map { |occurrence| OccurrenceData.new(occurrence) }
          @semantic_nodes = index.semantic_nodes.map { |semantic| SemanticNodeData.new(semantic) }
          @receiver_occurrences = index.receiver_occurrences.map { |receiver| ReceiverOccurrenceData.new(receiver) }
          @inlay_hints = index.inlay_hints.map { |hint| InlayHintData.new(hint) }
          @semantic_tokens = index.semantic_tokens.map { |token| SemanticTokenData.new(token) }
          @hierarchy_items = index.hierarchy.items.map { |item| HierarchyItemData.new(item) }
          @hierarchy_relations = index.hierarchy.relations.map { |relation| HierarchyRelationData.new(relation) }
          @captured_symbols = index.captured_symbols.map { |symbol| SymbolData.new(symbol) }
          @surface_declarations = snapshot.syntax_surface.declarations.map { |declaration| SurfaceDeclarationData.new(declaration) }
          @surface_scopes = snapshot.syntax_surface.scopes.map { |scope| SurfaceScopeData.new(scope) }
          @semantic_ready = snapshot.semantic_ready?
        end

        def to_snapshot : Compiler::Snapshot
          source_files = @files.map(&.to_file)
          entrypoint = source_files.find { |file| file.path == @entrypoint }
          raise ArgumentError.new("analysis entrypoint #{@entrypoint.inspect} is absent from files") unless entrypoint
          source = Source::CompilationUnit.new(
            source_files,
            entrypoint,
            @requires.map(&.to_directive),
            @edges.map(&.to_edge)
          )
          surface = Frontend::SyntaxSurface::Index.new(
            @surface_declarations.map(&.to_declaration),
            @surface_scopes.map(&.to_scope)
          )
          index = Compiler::Editor::Index.projected(
            @declarations.map(&.to_declaration),
            @references.map(&.to_reference),
            @occurrences.map(&.to_occurrence),
            @semantic_nodes.map(&.to_semantic_node),
            @receiver_occurrences.map(&.to_receiver_occurrence),
            @inlay_hints.map(&.to_inlay_hint),
            @semantic_tokens.map(&.to_semantic_token),
            @captured_symbols.map(&.to_symbol).to_set,
            surface
          )
          index.import_hierarchy(
            Compiler::Editor::Index::HierarchyFacts.new(
              @hierarchy_items.map(&.to_item),
              @hierarchy_relations.map(&.to_relation)
            )
          )
          Compiler::Snapshot.new(
            source: source,
            diagnostics: @diagnostics.map(&.to_diagnostic),
            editor_index: index,
            syntax_surface: surface,
            editor_semantic: @semantic_ready
          )
        end
      end

      def self.dump(snapshot : Compiler::Snapshot) : String
        Payload.new(snapshot).to_json
      end

      def self.load(source : String) : Compiler::Snapshot
        Payload.from_json(source).to_snapshot
      end
    end
  end
end
