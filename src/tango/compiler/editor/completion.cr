module Tango
  module Compiler
    module Editor
      # Protocol-neutral projections for completion and signature help. Inputs
      # are immutable editor indices plus the lexical current-buffer context;
      # no query compiles source or walks semantic compiler structures.
      module Completion
        enum ItemKind
          Class
          Enum
          EnumMember
          Module
          Function
          Method
          Field
          Variable
          Package
        end

        record Item,
          label : String,
          kind : ItemKind,
          detail : String? = nil,
          documentation : String? = nil,
          insert_text : String? = nil

        record Result, items : Array(Item), incomplete : Bool

        alias Parameter = Callables::Parameter
        record Signature,
          label : String,
          parameters : Array(Parameter),
          documentation : String? = nil,
          declaration : Index::SymbolId? = nil
        record SignatureResult,
          signatures : Array(Signature),
          active_signature : Int32,
          active_parameter : Int32

        def self.complete(
          context : Context,
          surface : Frontend::SyntaxSurface::Index,
          index : Index,
          receiver : Index::Receiver?,
          path : String,
          offset : Int32,
          bundled_packages : Array(String),
        ) : Result
          items, incomplete = case context.completion_kind
                              when .require?
                                {package_items(bundled_packages), false}
                              when .member?
                                receiver ? {member_items(surface, index, receiver, path, offset), false} : {[] of Item, true}
                              when .bare?
                                {bare_items(surface, path, offset), false}
                              else
                                {[] of Item, false}
                              end
          prefix = context.prefix
          filtered = items.select { |item| prefix.empty? || item.label.starts_with?(prefix) }
          Result.new(filtered.sort_by { |item| {item.label, item.detail.to_s} }, incomplete)
        end

        def self.signature_help(
          context : Context,
          surface : Frontend::SyntaxSurface::Index,
          index : Index,
          receiver : Index::Receiver?,
          resolved : Index::SymbolId?,
          path : String,
          offset : Int32,
        ) : SignatureResult?
          name = context.call_name
          return unless name

          site = Callables::Site.new(name, receiver, resolved)
          candidates = Callables.candidates(site, surface, index, path, offset)
          return if candidates.empty?
          active = Callables.active_index(site, candidates)
          max_parameter = candidates[active].parameters.size
          parameter = max_parameter == 0 ? 0 : context.active_parameter.clamp(0, max_parameter - 1)
          signatures = candidates.map do |candidate|
            Signature.new(
              candidate.label,
              candidate.parameters,
              candidate.documentation,
              candidate.declaration
            )
          end
          SignatureResult.new(signatures, active, parameter)
        end

        private def self.package_items(packages : Array(String)) : Array(Item)
          packages.map { |package| Item.new(package, ItemKind::Package, "bundled Tango package", insert_text: package) }
        end

        private def self.bare_items(
          surface : Frontend::SyntaxSurface::Index,
          path : String,
          offset : Int32,
        ) : Array(Item)
          current_type = surface.enclosing_type(path, offset)
          declarations = surface.visible_declarations(path, offset)
          if current_type
            declarations += surface.declarations.select do |declaration|
              declaration.kind.method? && declaration.container == current_type &&
                !declaration.callable_kind.try(&.initializer?) &&
                visible?(declaration, current_type, path)
            end
          end
          unique_items(declarations.map { |declaration| item_from_surface(declaration) })
        end

        private def self.member_items(
          surface : Frontend::SyntaxSurface::Index,
          index : Index,
          receiver : Index::Receiver,
          path : String,
          offset : Int32,
        ) : Array(Item)
          Callables.members(surface, index, receiver, path, offset).map do |candidate|
            Item.new(
              candidate.name,
              ItemKind::Method,
              candidate.label,
              candidate.documentation
            )
          end
        end

        private def self.item_from_surface(declaration : Frontend::SyntaxSurface::Declaration) : Item
          Item.new(
            declaration.name,
            item_kind(declaration.kind),
            declaration.detail,
            declaration.documentation
          )
        end

        private def self.item_kind(kind : Frontend::SyntaxSurface::DeclarationKind) : ItemKind
          case kind
          in .class?       then ItemKind::Class
          in .enum?        then ItemKind::Enum
          in .enum_member? then ItemKind::EnumMember
          in .module?      then ItemKind::Module
          in .function?    then ItemKind::Function
          in .method?      then ItemKind::Method
          in .field?       then ItemKind::Field
          in .local?       then ItemKind::Variable
          in .parameter?   then ItemKind::Variable
          end
        end

        private def self.unique_items(items : Array(Item)) : Array(Item)
          items.uniq { |item| {item.label, item.kind} }
        end

        private def self.visible?(
          declaration : Frontend::SyntaxSurface::Declaration,
          current_type : String?,
          path : String,
        ) : Bool
          return true unless declaration.visibility.private?
          declaration.container ? declaration.container == current_type : declaration.selection_range.path == path
        end
      end
    end
  end
end
