module Tango
  module Frontend
    # Crystal-free description of what is explicitly present in source. It is
    # safe for editor queries to consume, but deliberately carries no resolved
    # identity, inferred type, dispatch, or narrowing information.
    module SyntaxSurface
      enum DeclarationKind
        Class
        Enum
        EnumMember
        Module
        Function
        Method
        Field
        Local
        Parameter
      end

      enum ScopeKind
        Class
        Enum
        Module
        Callable
      end

      enum Visibility
        Public
        Protected
        Private
      end

      enum CallableKind
        Function
        InstanceMethod
        ClassMethod
        Initializer
      end

      record Parameter,
        name : String,
        explicit_type : String? = nil,
        documentation : String? = nil

      record Declaration,
        name : String,
        kind : DeclarationKind,
        range : Source::Range,
        selection_range : Source::Range,
        container : String? = nil,
        detail : String? = nil,
        documentation : String? = nil,
        explicit_type : String? = nil,
        outline : Bool = true,
        visibility : Visibility = Visibility::Public,
        callable_kind : CallableKind? = nil,
        parameters : Array(Parameter) = [] of Parameter,
        scope_id : String? = nil

      record Scope,
        kind : ScopeKind,
        range : Source::Range,
        container : String?,
        id : String? = nil

      class Index
        getter declarations : Array(Declaration)
        getter scopes : Array(Scope)

        def initialize(
          @declarations : Array(Declaration) = [] of Declaration,
          @scopes : Array(Scope) = [] of Scope,
        )
        end

        def declarations_in(path : String, outline_only : Bool = false) : Array(Declaration)
          @declarations.select do |declaration|
            declaration.selection_range.path == path && (!outline_only || declaration.outline)
          end
        end

        # Syntax enumerates only lexical candidates here; it does not claim
        # that a name resolves. Locals and parameters are limited to the
        # innermost callable containing the cursor and declarations that have
        # already appeared in source.
        def visible_declarations(path : String, offset : Int32) : Array(Declaration)
          callable = @scopes
            .select { |scope| scope.kind.callable? && scope.range.contains?(path, offset) }
            .min_by?(&.range.length)

          @declarations.select do |declaration|
            next false unless declaration.selection_range.path == path || global?(declaration)

            case declaration.kind
            when .local?, .parameter?
              declaration.selection_range.path == path &&
                declaration.scope_id == callable.try(&.id) &&
                declaration.selection_range.start_offset <= offset
            when .field?, .method?, .enum_member?
              false
            else
              true
            end
          end
        end

        # Documentation enrichment is a source-location join, not a semantic
        # name lookup. Overloads and same-named declarations cannot collide.
        def declaration_at(range : Source::Range) : Declaration?
          @declarations.find do |declaration|
            selection = declaration.selection_range
            selection.path == range.path &&
              selection.start_offset == range.start_offset &&
              selection.end_offset == range.end_offset
          end
        end

        def enclosing_type(path : String, offset : Int32) : String?
          @scopes
            .select { |scope| scope.kind.class? && scope.range.contains?(path, offset) }
            .min_by?(&.range.length)
            .try(&.container)
        end

        private def global?(declaration : Declaration) : Bool
          declaration.kind.class? || declaration.kind.enum? || declaration.kind.module? || declaration.kind.function?
        end
      end
    end
  end
end
