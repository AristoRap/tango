module Tango
  module Frontend
    module Crystal
      # The one parser-owned source walk used to preserve declarations Crystal
      # does not instantiate. Only SyntaxSurface records cross this boundary.
      module SyntaxSurfaceBuilder
        record Build,
          index : SyntaxSurface::Index,
          roots : Hash(String, ::Crystal::ASTNode)

        def self.build(source : Source::CompilationUnit) : SyntaxSurface::Index
          build_with_roots(source).index
        end

        def self.build_with_roots(source : Source::CompilationUnit) : Build
          declarations = [] of SyntaxSurface::Declaration
          scopes = [] of SyntaxSurface::Scope
          roots = {} of String => ::Crystal::ASTNode

          source.files.each do |file|
            begin
              parser = ::Crystal::Parser.new(file.code)
              parser.filename = file.path
              parser.wants_doc = true
              root = parser.parse
              roots[file.identity] = root
              root.accept(Visitor.new(file, declarations, scopes))
            rescue ::Crystal::CodeError
              # The current diagnostic snapshot owns parse failure reporting.
              # A failed file contributes no guessed surface declarations.
            end
          end

          Build.new(SyntaxSurface::Index.new(declarations, scopes), roots)
        end

        private class Visitor < ::Crystal::Visitor
          private class TraversalState
            getter containers = [] of String
            getter callable_scopes = [] of String
            getter local_keys = Set({String, String}).new
            getter visibilities = [] of ::Crystal::Visibility
          end

          def initialize(
            @file : Source::File,
            @declarations : Array(SyntaxSurface::Declaration),
            @scopes : Array(SyntaxSurface::Scope),
          )
            @state = TraversalState.new
          end

          def visit(node : ::Crystal::ClassDef) : Bool
            segments = node.name.names
            name = segments.last
            container = joined_container(segments[0...-1])
            range = node_range(node)
            selection = location_range(node.name.location, name)
            if range && selection
              detail = String.build do |io|
                io << (node.struct? ? "struct " : "class ") << node.name
                node.superclass.try { |superclass| io << " < " << superclass }
              end
              @declarations << SyntaxSurface::Declaration.new(
                name,
                node.struct? ? SyntaxSurface::DeclarationKind::Struct : SyntaxSurface::DeclarationKind::Class,
                range,
                selection,
                container,
                detail,
                node.doc
              )
              scope_kind = node.struct? ? SyntaxSurface::ScopeKind::Struct : SyntaxSurface::ScopeKind::Class
              @scopes << SyntaxSurface::Scope.new(scope_kind, range, qualified_name(name, container))
            end

            segments.each { |segment| @state.containers << segment }
            true
          end

          def end_visit(node : ::Crystal::ClassDef) : Nil
            node.name.names.size.times { @state.containers.pop }
          end

          def visit(node : ::Crystal::EnumDef) : Bool
            segments = node.name.names
            name = segments.last
            container = joined_container(segments[0...-1])
            range = node_range(node)
            selection = location_range(node.name.location, name)
            if range && selection
              qualified = qualified_name(name, container)
              @declarations << SyntaxSurface::Declaration.new(
                name,
                SyntaxSurface::DeclarationKind::Enum,
                range,
                selection,
                container,
                "enum #{node.name}",
                node.doc
              )
              @scopes << SyntaxSurface::Scope.new(SyntaxSurface::ScopeKind::Enum, range, qualified)
              node.members.each do |member|
                next unless argument = member.as?(::Crystal::Arg)
                next unless member_range = location_range(argument.location, argument.name)
                @declarations << SyntaxSurface::Declaration.new(
                  argument.name,
                  SyntaxSurface::DeclarationKind::EnumMember,
                  member_range,
                  member_range,
                  qualified,
                  "#{qualified}::#{argument.name}"
                )
              end
            end

            segments.each { |segment| @state.containers << segment }
            true
          end

          def end_visit(node : ::Crystal::EnumDef) : Nil
            node.name.names.size.times { @state.containers.pop }
          end

          def visit(node : ::Crystal::ModuleDef) : Bool
            segments = node.name.names
            name = segments.last
            container = joined_container(segments[0...-1])
            range = node_range(node)
            selection = location_range(node.name.location, name)
            if range && selection
              @declarations << SyntaxSurface::Declaration.new(
                name,
                SyntaxSurface::DeclarationKind::Module,
                range,
                selection,
                container,
                "module #{node.name}",
                node.doc
              )
              @scopes << SyntaxSurface::Scope.new(SyntaxSurface::ScopeKind::Module, range, qualified_name(name, container))
            end

            segments.each { |segment| @state.containers << segment }
            true
          end

          def end_visit(node : ::Crystal::ModuleDef) : Nil
            node.name.names.size.times { @state.containers.pop }
          end

          def visit(node : ::Crystal::Def) : Bool
            pushed = push_receiver(node.receiver)
            container = current_container
            range = node_range(node)
            selection = location_range(node.name_location, node.name)
            kind = container ? SyntaxSurface::DeclarationKind::Method : SyntaxSurface::DeclarationKind::Function
            callable_kind = if container
                              if node.name == "initialize" && !node.receiver
                                SyntaxSurface::CallableKind::Initializer
                              else
                                node.receiver ? SyntaxSurface::CallableKind::ClassMethod : SyntaxSurface::CallableKind::InstanceMethod
                              end
                            else
                              SyntaxSurface::CallableKind::Function
                            end
            if range && selection
              scope_id = "#{@file.path}:#{range.start_offset}"
              @declarations << SyntaxSurface::Declaration.new(
                node.name,
                kind,
                range,
                selection,
                container,
                signature(node),
                node.doc,
                node.return_type.try(&.to_s),
                visibility: visibility(@state.visibilities.last? || node.visibility),
                callable_kind: callable_kind,
                parameters: node.args.map { |arg| SyntaxSurface::Parameter.new(arg.name, arg.restriction.try(&.to_s)) },
                scope_id: scope_id
              )
              @scopes << SyntaxSurface::Scope.new(SyntaxSurface::ScopeKind::Callable, range, qualified_name(node.name, container), scope_id)
              @state.callable_scopes << scope_id
            end

            node.args.each do |arg|
              next unless arg_range = location_range(arg.location, arg.name)
              @declarations << SyntaxSurface::Declaration.new(
                arg.name,
                SyntaxSurface::DeclarationKind::Parameter,
                arg_range,
                arg_range,
                qualified_name(node.name, container),
                explicit_type: arg.restriction.try(&.to_s),
                outline: false,
                scope_id: @state.callable_scopes.last?
              )
            end

            pushed.times { @state.containers.pop }
            true
          end

          def end_visit(node : ::Crystal::Def) : Nil
            @state.callable_scopes.pop unless @state.callable_scopes.empty?
          end

          def visit(node : ::Crystal::VisibilityModifier) : Bool
            @state.visibilities << node.modifier
            true
          end

          def end_visit(node : ::Crystal::VisibilityModifier) : Nil
            @state.visibilities.pop
          end

          def visit(node : ::Crystal::Assign) : Bool
            variable = node.target.as?(::Crystal::Var)
            if variable
              add_local(variable.name, variable.location, nil)
              return true
            end

            if path = node.target.as?(::Crystal::Path)
              add_named_declaration(path, SyntaxSurface::DeclarationKind::Constant, node_range(node), path.to_s)
            end
            true
          end

          def visit(node : ::Crystal::Alias) : Bool
            add_named_declaration(node.name, SyntaxSurface::DeclarationKind::TypeAlias, node_range(node), "alias #{node.name} = #{node.value}")
            true
          end

          def visit(node : ::Crystal::TypeDeclaration) : Bool
            variable = node.var
            kind, raw_name = case variable
                             when ::Crystal::InstanceVar
                               {SyntaxSurface::DeclarationKind::Field, variable.name}
                             when ::Crystal::Var
                               {SyntaxSurface::DeclarationKind::Local, variable.name}
                             else
                               return true
                             end
            name = raw_name.lstrip('@')
            selection = location_range(variable.location, raw_name)
            if selection
              @declarations << SyntaxSurface::Declaration.new(
                name,
                kind,
                selection,
                selection,
                current_container,
                explicit_type: node.declared_type.to_s,
                outline: kind.field?,
                scope_id: kind.local? ? @state.callable_scopes.last? : nil
              )
            end
            true
          end

          def visit(node : ::Crystal::ASTNode) : Bool
            true
          end

          private def signature(node : ::Crystal::Def) : String
            String.build do |io|
              io << "def " << node.name << '('
              node.args.join(io, ", ") do |arg, output|
                output << arg.name
                arg.restriction.try { |restriction| output << " : " << restriction }
              end
              io << ')'
              node.return_type.try { |return_type| io << " : " << return_type }
            end
          end

          private def add_named_declaration(path : ::Crystal::Path, kind : SyntaxSurface::DeclarationKind, range : Source::Range?, detail : String) : Nil
            name = path.names.last
            selection = location_range(path.location, path.to_s).try do |full|
              Source::Range.new(full.path, full.end_offset - name.bytesize, full.end_offset, full.line, full.column.try { |column| column + path.to_s.bytesize - name.bytesize })
            end
            return unless range && selection
            container = joined_container(path.names[0...-1])
            @declarations << SyntaxSurface::Declaration.new(name, kind, range, selection, container, detail)
          end

          private def add_local(name : String, location : ::Crystal::Location?, explicit_type : String?) : Nil
            scope = @state.callable_scopes.last? || @file.path
            return unless @state.local_keys.add?({scope, name})
            selection = location_range(location, name)
            return unless selection

            @declarations << SyntaxSurface::Declaration.new(
              name,
              SyntaxSurface::DeclarationKind::Local,
              selection,
              selection,
              current_container,
              explicit_type: explicit_type,
              outline: false,
              scope_id: @state.callable_scopes.last?
            )
          end

          private def visibility(value : ::Crystal::Visibility) : SyntaxSurface::Visibility
            case value
            when .private?   then SyntaxSurface::Visibility::Private
            when .protected? then SyntaxSurface::Visibility::Protected
            else                  SyntaxSurface::Visibility::Public
            end
          end

          private def push_receiver(receiver : ::Crystal::ASTNode?) : Int32
            path = receiver.as?(::Crystal::Path)
            return 0 unless path
            path.names.each { |segment| @state.containers << segment }
            path.names.size
          end

          private def current_container : String?
            @state.containers.empty? ? nil : @state.containers.join("::")
          end

          private def joined_container(extra : Array(String)) : String?
            names = @state.containers + extra
            names.empty? ? nil : names.join("::")
          end

          private def qualified_name(name : String, container : String?) : String
            container ? "#{container}::#{name}" : name
          end

          private def location_range(location : ::Crystal::Location?, token : String) : Source::Range?
            return nil unless location
            column = @file.byte_column_at(location.line_number, location.column_number)
            @file.range_at(location.line_number, column, token.bytesize)
          end

          private def node_range(node : ::Crystal::ASTNode) : Source::Range?
            location = node.location
            finish = node.end_location
            return nil unless location && finish

            start_column = @file.byte_column_at(location.line_number, location.column_number)
            end_column = @file.byte_column_at(finish.line_number, finish.column_number)
            start_offset = @file.line_index.byte_offset_at(location.line_number, start_column)
            end_offset = @file.line_index.byte_offset_at(finish.line_number, end_column) + 1
            Source::Range.new(
              @file.path,
              start_offset,
              end_offset.clamp(start_offset, @file.code.bytesize),
              location.line_number,
              start_column
            )
          end
        end
      end
    end
  end
end
