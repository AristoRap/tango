module Tango
  module Compiler
    module Editor
      # Source-level rename families derived from semantic declarations and the
      # parser-owned syntax surface. Index remains the data owner; this reopening
      # isolates family grouping, collision domains, and uninstantiated ranges.
      class Index
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
      end
    end
  end
end
