module Tango
  module Transport
    @[JSON::Serializable::Options(emit_nulls: true)]
    class SurfaceParameterData
      include JSON::Serializable
      include JSON::Serializable::Strict

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

    @[JSON::Serializable::Options(emit_nulls: true)]
    class SurfaceDeclarationData
      include JSON::Serializable
      include JSON::Serializable::Strict

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

    @[JSON::Serializable::Options(emit_nulls: true)]
    class SurfaceScopeData
      include JSON::Serializable
      include JSON::Serializable::Strict

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

    @[JSON::Serializable::Options(emit_nulls: true)]
    class SurfaceData
      include JSON::Serializable
      include JSON::Serializable::Strict

      getter declarations : Array(SurfaceDeclarationData)
      getter scopes : Array(SurfaceScopeData)

      def initialize(surface : Frontend::SyntaxSurface::Index)
        @declarations = surface.declarations.map { |declaration| SurfaceDeclarationData.new(declaration) }
        @scopes = surface.scopes.map { |scope| SurfaceScopeData.new(scope) }
      end

      def to_surface : Frontend::SyntaxSurface::Index
        Frontend::SyntaxSurface::Index.new(
          @declarations.map(&.to_declaration),
          @scopes.map(&.to_scope)
        )
      end
    end
  end
end
