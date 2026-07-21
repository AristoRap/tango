require "json"

module Tango
  module Lsp
    # JSON transport for the immutable editor projection produced in an
    # isolated analysis process. This deliberately excludes Crystal semantic
    # objects, NIR, Facts, Plans, and LIR; requests consume only the source,
    # diagnostics, syntax catalog, and semantic editor index they need.
    module AnalysisCodec
      class RangeData
        include JSON::Serializable
        getter path : String
        getter start_offset : Int32
        getter end_offset : Int32
        getter line : Int32?
        getter column : Int32?

        def initialize(range : Source::Range)
          @path = range.path
          @start_offset = range.start_offset
          @end_offset = range.end_offset
          @line = range.line
          @column = range.column
        end

        def to_range : Source::Range
          Source::Range.new(@path, @start_offset, @end_offset, @line, @column)
        end
      end

      class TypeData
        include JSON::Serializable
        getter family : String
        getter width : String?
        getter name : String?
        getter members : Array(TypeData)
        getter type_args : Array(TypeData)

        def initialize(type : IR::Type)
          @family = type.family.to_s
          @width = type.width.try(&.to_s)
          @name = type.name
          @members = type.members.map { |member| TypeData.new(member).as(TypeData) }
          @type_args = type.type_args.map { |argument| TypeData.new(argument).as(TypeData) }
        end

        def to_type : IR::Type
          IR::Type.new(
            IR::Type::Family.parse(@family),
            @width.try { |value| IR::Type::Width.parse(value) },
            @name,
            @members.map(&.to_type),
            @type_args.map(&.to_type)
          )
        end
      end

      class SymbolData
        include JSON::Serializable
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

      class SurfaceParameterData
        include JSON::Serializable
        getter name : String
        getter explicit_type : String?
        getter documentation : String?

        def initialize(parameter : Frontend::SyntaxSurface::Parameter)
          @name = parameter.name
          @explicit_type = parameter.explicit_type
          @documentation = parameter.documentation
        end

        def to_parameter : Frontend::SyntaxSurface::Parameter
          Frontend::SyntaxSurface::Parameter.new(@name, @explicit_type, @documentation)
        end
      end

      class SurfaceDeclarationData
        include JSON::Serializable
        getter name : String
        getter kind : String
        getter range : RangeData
        getter selection_range : RangeData
        getter container : String?
        getter detail : String?
        getter documentation : String?
        getter explicit_type : String?
        getter outline : Bool
        getter visibility : String
        getter callable_kind : String?
        getter parameters : Array(SurfaceParameterData)
        getter scope_id : String?

        def initialize(declaration : Frontend::SyntaxSurface::Declaration)
          @name = declaration.name
          @kind = declaration.kind.to_s
          @range = RangeData.new(declaration.range)
          @selection_range = RangeData.new(declaration.selection_range)
          @container = declaration.container
          @detail = declaration.detail
          @documentation = declaration.documentation
          @explicit_type = declaration.explicit_type
          @outline = declaration.outline
          @visibility = declaration.visibility.to_s
          @callable_kind = declaration.callable_kind.try(&.to_s)
          @parameters = declaration.parameters.map { |parameter| SurfaceParameterData.new(parameter) }
          @scope_id = declaration.scope_id
        end

        def to_declaration : Frontend::SyntaxSurface::Declaration
          Frontend::SyntaxSurface::Declaration.new(
            @name,
            Frontend::SyntaxSurface::DeclarationKind.parse(@kind),
            @range.to_range,
            @selection_range.to_range,
            @container,
            @detail,
            @documentation,
            @explicit_type,
            @outline,
            Frontend::SyntaxSurface::Visibility.parse(@visibility),
            @callable_kind.try { |kind| Frontend::SyntaxSurface::CallableKind.parse(kind) },
            @parameters.map(&.to_parameter),
            @scope_id
          )
        end
      end

      class SurfaceScopeData
        include JSON::Serializable
        getter kind : String
        getter range : RangeData
        getter container : String?
        getter id : String?

        def initialize(scope : Frontend::SyntaxSurface::Scope)
          @kind = scope.kind.to_s
          @range = RangeData.new(scope.range)
          @container = scope.container
          @id = scope.id
        end

        def to_scope : Frontend::SyntaxSurface::Scope
          Frontend::SyntaxSurface::Scope.new(
            Frontend::SyntaxSurface::ScopeKind.parse(@kind),
            @range.to_range,
            @container,
            @id
          )
        end
      end

      class DiagnosticData
        include JSON::Serializable
        getter origin : String
        getter severity : String
        getter code : String
        getter message : String
        getter file : String?
        getter line : Int32
        getter column : Int32
        getter size : Int32
        getter detail : String?
        getter unnecessary : Bool
        getter range : RangeData?
        getter related : Array(RelatedDiagnosticData)
        getter hints : Array(String)
        getter fix : DiagnosticFixData?

        def initialize(diagnostic : Diagnostic)
          @origin = diagnostic.origin.to_s
          @severity = diagnostic.severity.to_s
          @code = diagnostic.code
          @message = diagnostic.message
          @file = diagnostic.file
          @line = diagnostic.line
          @column = diagnostic.column
          @size = diagnostic.size
          @detail = diagnostic.detail
          @unnecessary = diagnostic.unnecessary
          @range = diagnostic.range.try { |range| RangeData.new(range) }
          @related = diagnostic.related.map { |range, message| RelatedDiagnosticData.new(range, message) }
          @hints = diagnostic.hints
          @fix = diagnostic.fix.try { |fix| DiagnosticFixData.new(fix) }
        end

        def to_diagnostic : Diagnostic
          Diagnostic.new(
            Diagnostic::Origin.parse(@origin),
            Diagnostic::Severity.parse(@severity),
            @code,
            @message,
            @file,
            @line,
            @column,
            @size,
            @detail,
            @unnecessary,
            @range.try(&.to_range),
            @related.map(&.to_related),
            hints: @hints,
            fix: @fix.try(&.to_fix)
          )
        end
      end

      class RelatedDiagnosticData
        include JSON::Serializable
        getter range : RangeData
        getter message : String

        def initialize(range : Source::Range, @message : String)
          @range = RangeData.new(range)
        end

        def to_related : {Source::Range, String}
          {@range.to_range, @message}
        end
      end

      class DiagnosticFixEditData
        include JSON::Serializable
        getter range : RangeData
        getter new_text : String

        def initialize(edit : Diagnostic::FixEdit)
          @range = RangeData.new(edit.range)
          @new_text = edit.new_text
        end

        def to_edit : Diagnostic::FixEdit
          Diagnostic::FixEdit.new(@range.to_range, @new_text)
        end
      end

      class DiagnosticFixData
        include JSON::Serializable
        getter kind : String
        getter title : String
        getter edits : Array(DiagnosticFixEditData)

        def initialize(fix : Diagnostic::Fix)
          @kind = fix.kind.to_s
          @title = fix.title
          @edits = fix.edits.map { |edit| DiagnosticFixEditData.new(edit) }
        end

        def to_fix : Diagnostic::Fix
          Diagnostic::Fix.new(
            Diagnostic::FixKind.parse(@kind),
            @title,
            @edits.map(&.to_edit)
          )
        end
      end

      class FileData
        include JSON::Serializable
        getter path : String
        getter code : String
        getter identity : String
        getter stable_path : Bool

        def initialize(file : Source::File)
          @path = file.path
          @code = file.code
          @identity = file.identity
          @stable_path = file.stable_path?
        end

        def to_file : Source::File
          Source::File.new(@path, @code, @identity, @stable_path)
        end
      end

      class RequireData
        include JSON::Serializable
        getter from : String
        getter request : String
        getter range : RangeData

        def initialize(directive : Source::RequireDirective)
          @from = directive.from
          @request = directive.request
          @range = RangeData.new(directive.range)
        end

        def to_directive : Source::RequireDirective
          Source::RequireDirective.new(@from, @request, @range.to_range)
        end
      end

      class EdgeData
        include JSON::Serializable
        getter from : String
        getter request : String
        getter to : String
        getter range : RangeData

        def initialize(edge : Source::RequireEdge)
          @from = edge.from
          @request = edge.request
          @to = edge.to
          @range = RangeData.new(edge.range)
        end

        def to_edge : Source::RequireEdge
          Source::RequireEdge.new(@from, @request, @to, @range.to_range)
        end
      end

      class Payload
        include JSON::Serializable
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
