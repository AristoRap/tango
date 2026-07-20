# Accessor declarations are deliberately explicit in Tango source. Crystal's
# native macro expander turns these into typed ivars and ordinary defs before
# Tango builds NIR; the compiler never needs an accessor-specific node or
# target path.
macro getter(*decls)
  {% for decl in decls %}
    {% decl.raise "tango accessors require a type declaration (`getter x : T`)" unless decl.is_a?(TypeDeclaration) %}
    @{{decl.var.id}} : {{decl.type}}{% if decl.value %} = {{decl.value}}{% end %}

    def {{decl.var.id}} : {{decl.type}}
      @{{decl.var.id}}
    end
  {% end %}
end

macro setter(*decls)
  {% for decl in decls %}
    {% decl.raise "tango accessors require a type declaration (`setter x : T`)" unless decl.is_a?(TypeDeclaration) %}
    @{{decl.var.id}} : {{decl.type}}{% if decl.value %} = {{decl.value}}{% end %}

    def {{decl.var.id}}=(__value : {{decl.type}}) : {{decl.type}}
      @{{decl.var.id}} = __value
      @{{decl.var.id}}
    end
  {% end %}
end

macro property(*decls)
  {% for decl in decls %}
    {% decl.raise "tango accessors require a type declaration (`property x : T`)" unless decl.is_a?(TypeDeclaration) %}
    @{{decl.var.id}} : {{decl.type}}{% if decl.value %} = {{decl.value}}{% end %}

    def {{decl.var.id}} : {{decl.type}}
      @{{decl.var.id}}
    end

    def {{decl.var.id}}=(__value : {{decl.type}}) : {{decl.type}}
      @{{decl.var.id}} = __value
      @{{decl.var.id}}
    end
  {% end %}
end
