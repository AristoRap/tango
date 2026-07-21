module Tango
  module Frontend
    module Crystal
      class ToNIR
        include TypeBridge
        include CapabilityTranslation
        include YieldTranslation
        include SelectTranslation
        include HashTranslation
        include CoreDispatchTranslation
        include CallTranslation
        include SourceLocations

        private class TranslationState
          getter ids = NodeIdSequence.new("nir")
          getter pending_defs = [] of ::Crystal::Def
          getter seen_defs = Set(UInt64).new
          getter class_names = Set(String).new
          getter owner_classes = {} of String => IR::NIR::Class
          getter loop_ids = {} of UInt64 => NodeId
          getter type_annotations = {} of IR::Type => Array(IR::NIR::TargetAnnotation)
          getter type_aliases = {} of Array(String) => IR::Type

          def queue(definition : ::Crystal::Def) : Nil
            pending_defs << definition if seen_defs.add?(definition.object_id)
          end
        end

        private class DefinitionContext
          getter owner : String?
          getter yield_param : IR::NIR::BlockParam?

          def initialize(@owner : String? = nil, @yield_param : IR::NIR::BlockParam? = nil)
          end
        end

        def self.translate(result : ::Crystal::Compiler::Result, source : Source::CompilationUnit) : IR::NIR::Program
          new(source).translate_top_level(result.node)
        end

        def initialize(@source : Source::CompilationUnit)
          @state = TranslationState.new
          @context = DefinitionContext.new
        end

        # Decompose Crystal::Expressions before source filtering: the root
        # wrapper may not carry the user source location, so filtering the
        # root directly could drop the whole program.
        #
        # A top-level Crystal::Def is an untyped template. Its typed instances
        # are reached from call sites; those are collected into a worklist and
        # translated after the main statements, then emitted ahead of them.
        def translate_top_level(node : ::Crystal::ASTNode) : IR::NIR::Program
          main_nodes = top_level_nodes(node).select do |child|
            # Typed Def instances are queued from resolved calls. Top-level
            # Annotation nodes are declaration metadata already attached to
            # those defs/classes, never executable statements of their own.
            next false if child.is_a?(::Crystal::Def) || child.is_a?(::Crystal::Annotation)
            child.is_a?(::Crystal::ClassDef) ? source_node?(child) : entry_source_node?(child)
          end
          main = translate_statements(main_nodes)

          defs = [] of IR::NIR::Stmt
          until @state.pending_defs.empty?
            defs << translate_def(@state.pending_defs.shift)
          end

          IR::NIR::Program.new(@state.owner_classes.values.map(&.as(IR::NIR::Stmt)) + defs + main, @state.type_annotations)
        end

        private def top_level_nodes(node : ::Crystal::ASTNode) : Array(::Crystal::ASTNode)
          nodes = [] of ::Crystal::ASTNode
          flatten_expressions(node, nodes)
          nodes
        end

        private def flatten_expressions(node : ::Crystal::ASTNode, into : Array(::Crystal::ASTNode)) : Nil
          case node
          when ::Crystal::Expressions
            node.expressions.each { |child| flatten_expressions(child, into) }
          when ::Crystal::Nop
            # structural filler, not a statement
          else
            into << node
          end
        end

        # Nested children inside an already accepted source node are trusted
        # without re-checking source_node?.
        private def translate_stmt(node : ::Crystal::ASTNode) : IR::NIR::Stmt
          case node
          when ::Crystal::Def
            translate_def(node)
          when ::Crystal::ClassDef
            translate_class(node)
          when ::Crystal::EnumDef
            translate_enum(node)
          when ::Crystal::ModuleDef
            translate_namespace(node)
          when ::Crystal::Alias
            translate_alias(node)
          when ::Crystal::Assign
            if constant_assignment?(node)
              translate_constant(node)
            else
              translate_expr(node)
            end
          when ::Crystal::While
            translate_while(node)
          when ::Crystal::Return
            translate_control_exit(node, IR::NIR::Return)
          when ::Crystal::Break
            translate_control_exit(node, IR::NIR::Break)
          when ::Crystal::Next
            translate_control_exit(node, IR::NIR::Next)
          else
            translate_expr(node)
          end
        end

        private def translate_expr(node : ::Crystal::ASTNode) : IR::NIR::Expr
          case node
          when ::Crystal::NumberLiteral
            type = type_of(node)
            if type.try(&.family.float?)
              IR::NIR::FloatLiteral.new(next_id, node.value, type, span(node))
            else
              IR::NIR::IntLiteral.new(next_id, node.value, type, span(node))
            end
          when ::Crystal::StringLiteral
            IR::NIR::StringLiteral.new(next_id, node.value, type_of(node), span(node))
          when ::Crystal::BoolLiteral
            IR::NIR::BoolLiteral.new(next_id, node.value, type_of(node), span(node))
          when ::Crystal::NilLiteral
            IR::NIR::NilLiteral.new(next_id, span(node))
          when ::Crystal::Var
            IR::NIR::Local.new(next_id, node.name, type_of(node), span(node), name_span: name_span(node.location, node.name))
          when ::Crystal::InstanceVar
            instance_var(node)
          when ::Crystal::Path
            translate_path(node)
          when ::Crystal::Assign
            translate_assign(node)
          when ::Crystal::If
            translate_if(node)
          when ::Crystal::ExceptionHandler
            translate_exception_handler(node)
          when ::Crystal::Not
            IR::NIR::Not.new(next_id, translate_expr(node.exp), type_of(node), span(node))
          when ::Crystal::IsA
            translate_type_test(node)
          when ::Crystal::Cast
            translate_cast(node)
          when ::Crystal::Call
            translate_call(node)
          when ::Crystal::Yield
            translate_yield(node)
          when ::Crystal::Expressions
            translate_value_sequence(node)
          else
            unsupported(node)
          end
        end

        private def translate_value_sequence(node : ::Crystal::Expressions) : IR::NIR::Expr
          expressions = node.expressions.reject(::Crystal::Nop)
          return unsupported(node) if expressions.empty?

          value = translate_expr(expressions.last)
          prefix = IR::NIR::Block.new(next_id, translate_statements(expressions[0...-1]), span(node))
          IR::NIR::ValueSequence.new(next_id, prefix, value, type_of(node), span(node))
        end

        private def translate_assign(node : ::Crystal::Assign) : IR::NIR::Expr
          target = node.target
          case target
          when ::Crystal::Var
            local = IR::NIR::Local.new(next_id, target.name, type_of(target), span(target), name_span: name_span(target.location, target.name))
            IR::NIR::Assign.new(next_id, local, translate_expr(node.value), type_of(node), span(node))
          when ::Crystal::InstanceVar
            ivar = instance_var(target)
            IR::NIR::Assign.new(next_id, ivar, translate_expr(node.value), type_of(node), span(node))
          else
            unsupported(node)
          end
        end

        private def instance_var(node : ::Crystal::InstanceVar) : IR::NIR::InstanceVar
          IR::NIR::InstanceVar.new(
            next_id,
            node.name.lchop('@'),
            @context.owner.to_s,
            type_of(node),
            span(node),
            name_span: name_span(node.location, node.name)
          )
        end

        private def translate_if(node : ::Crystal::If) : IR::NIR::Expr
          cond = translate_expr(node.cond)
          then_branch = translate_block(node.then)
          else_branch = node.else.is_a?(::Crystal::Nop) ? nil : translate_block(node.else)
          IR::NIR::If.new(next_id, cond, then_branch, else_branch, type_of(node), span(node))
        end

        # Primitive calls are receiverless and positional, optionally with an inline
        # block. Receivers, named args, and block args make the whole call
        # unsupported rather than silently dropping call surface.
        private def translate_while(node : ::Crystal::While) : IR::NIR::While
          id = next_id
          @state.loop_ids[node.object_id] = id
          IR::NIR::While.new(id, translate_expr(node.cond), translate_block(node.body), span(node))
        end

        private def translate_control_exit(node : ::Crystal::ControlExpression, klass : IR::NIR::Return.class | IR::NIR::Break.class | IR::NIR::Next.class) : IR::NIR::Return | IR::NIR::Break | IR::NIR::Next
          value = node.exp.try { |exp| translate_expr(exp) }
          target = if node.is_a?(::Crystal::Break) || node.is_a?(::Crystal::Next)
                     @state.loop_ids[node.target.object_id]?
                   end
          klass.new(next_id, value, target, span(node))
        end

        private def translate_exception_handler(node : ::Crystal::ExceptionHandler) : IR::NIR::ExceptionHandler
          clauses = node.rescues.try do |rescues|
            rescues.map do |rescue_node|
              types = rescue_node.types.try do |paths|
                paths.compact_map { |path| path.type?.try { |type| build_type(type.instance_type) } }
              end || [] of IR::Type
              binding_type = types.size == 1 ? types.first : IR::Type.klass("Exception")
              binding = rescue_node.name.try do |name|
                IR::NIR::Local.new(next_id, name, binding_type, span(rescue_node), name_span: rescue_name_span(rescue_node, name))
              end
              IR::NIR::RescueClause.new(types, binding, translate_block(rescue_node.body))
            end
          end || [] of IR::NIR::RescueClause

          IR::NIR::ExceptionHandler.new(
            next_id,
            translate_block(node.body),
            clauses,
            node.else.try { |branch| translate_block(branch) },
            node.ensure.try { |branch| translate_block(branch) },
            type_of(node),
            span(node)
          )
        end

        private def translate_def(node : ::Crystal::Def) : IR::NIR::Def
          owner = node.owner?
          owner_type = if owner && !owner.is_a?(::Crystal::Program)
                         resolved_owner = node.receiver && owner.metaclass? ? owner.instance_type : owner
                         build_type(resolved_owner)
                       end
          register_owner_class(owner, owner_type)

          params = [] of IR::NIR::Param
          params << IR::NIR::Param.new(next_id, "self", owner_type, span(node)) if owner_type && !node.receiver
          node.args.each { |arg| params << IR::NIR::Param.new(next_id, arg.name, type_of(arg), span(arg), name_span: name_span(arg.location, arg.name)) }

          yields = collect_yields(node.body)
          block_param = if !yields.empty?
                          block_arg = node.block_arg
                          name = block_arg.try(&.name).presence || "__yield_block"
                          signature = yield_signature(node, yields)
                          IR::NIR::BlockParam.new(
                            next_id,
                            name,
                            signature,
                            block_arg.try { |arg| span(arg) } || span(node),
                            name_span: block_arg.try { |arg| name_span(arg.location, arg.name) },
                            yield_parameter: true,
                            value_required: yield_value_required?(block_arg, signature)
                          )
                        else
                          node.block_arg.try do |block_arg|
                            IR::NIR::BlockParam.new(next_id, block_arg.name, proc_signature(block_arg), span(block_arg), name_span: name_span(block_arg.location, block_arg.name))
                          end
                        end

          return_type = if owner_type && node.name == "initialize"
                          IR::Type::NIL
                        elsif nil_return_restriction?(node.return_type)
                          IR::Type::NIL
                        else
                          type_of(node)
                        end
          callable_kind = if node.name == "initialize"
                            IR::NIR::CallableKind::Initializer
                          elsif node.receiver
                            IR::NIR::CallableKind::ClassMethod
                          elsif owner_type
                            IR::NIR::CallableKind::InstanceMethod
                          else
                            IR::NIR::CallableKind::Function
                          end

          yield_param = block_param if block_param.try(&.yield_parameter?)
          body = with_definition_context(DefinitionContext.new(owner_type.try(&.name), yield_param)) do
            translate_block(node.body)
          end

          IR::NIR::Def.new(
            next_id,
            node.name,
            params,
            body,
            return_type,
            span(node) || expansion_span(node.location),
            block_param: block_param,
            name_span: name_span(node.name_location, node.name),
            owner: owner_type,
            callable_kind: callable_kind,
            capability_witnesses: capability_witnesses(node),
            namespace_path: definition_namespace_path(owner),
            return_type_reference: type_alias_reference(node.return_type, definition_namespace_path(owner))
          )
        end

        private def type_alias_reference(node : ::Crystal::ASTNode?, owner_path : Array(String)) : IR::NIR::TypeAliasReference?
          path = node.as?(::Crystal::Path)
          return unless path
          alias_type = path.target_type.as?(::Crystal::AliasType)
          alias_path = alias_type ? named_path(alias_type) : path.names.size > 1 ? path.names : owner_path + path.names
          target = alias_type ? build_type(alias_type.aliased_type) : @state.type_aliases[alias_path]?
          return unless target
          IR::NIR::TypeAliasReference.new(
            next_id,
            alias_path,
            target,
            span(path),
            path_name_span(path)
          )
        end

        private def translate_namespace(node : ::Crystal::ModuleDef) : IR::NIR::Namespace
          nodes = top_level_nodes(node.body).reject do |child|
            child.is_a?(::Crystal::Def) || child.is_a?(::Crystal::Annotation)
          end
          body = IR::NIR::Block.new(next_id, translate_statements(nodes), span(node.body))
          IR::NIR::Namespace.new(
            next_id,
            namespace_path(node.resolved_type),
            body,
            span(node),
            path_name_span(node.name)
          )
        end

        private def translate_alias(node : ::Crystal::Alias) : IR::NIR::TypeAlias
          resolved = node.resolved_type
          declaration = IR::NIR::TypeAlias.new(
            next_id,
            named_path(resolved),
            build_type(resolved.aliased_type),
            span(node),
            path_name_span(node.name)
          )
          @state.type_aliases[declaration.path] = declaration.target
          declaration
        end

        private def constant_assignment?(node : ::Crystal::Assign) : Bool
          node.target.as?(::Crystal::Path).try(&.target_const).try do |constant|
            !constant.namespace.is_a?(::Crystal::EnumType)
          end || false
        end

        private def translate_constant(node : ::Crystal::Assign) : IR::NIR::Constant
          target = node.target.as(::Crystal::Path)
          constant = target.target_const
          raise "constant assignment lost its resolved declaration" unless constant
          value = translate_expr(node.value)
          type = value.type || type_of(node.value) || IR::Type.unknown
          IR::NIR::Constant.new(
            next_id,
            named_path(constant),
            value,
            type,
            span(node),
            path_name_span(target)
          )
        end

        private def translate_class(node : ::Crystal::ClassDef) : IR::NIR::Class
          name = node.name.to_s
          @state.class_names << name

          fields = [] of IR::Field
          resolved = node.resolved_type
          if resolved.is_a?(::Crystal::InstanceVarContainer)
            resolved.all_instance_vars.each do |ivar_name, ivar|
              ivar_type = ivar.type?
              fields << IR::Field.new(ivar_name.lchop('@'), build_type(ivar_type)) if ivar_type
            end
          end

          reference = resolved ? !resolved.struct? : true
          initializers = translate_field_initializers(resolved, fields, name)
          superclass_type = resolved_superclass_type(node, resolved)
          IR::NIR::Class.new(
            next_id,
            name,
            superclass_type.try(&.to_s) || node.superclass.try(&.to_s),
            fields,
            span(node),
            name_span: name_span(node.name.location, name),
            reference: reference,
            initializers: initializers,
            concrete_type: resolved ? build_type(resolved.as(::Crystal::Type)) : IR::Type.klass(name),
            superclass_type: superclass_type
          )
        end

        private def translate_enum(node : ::Crystal::EnumDef) : IR::NIR::Enum
          resolved = node.resolved_type
          type = build_type(resolved)
          source_members = {} of String => Source::Range?
          node.members.each do |member|
            next unless argument = member.as?(::Crystal::Arg)
            source_members[argument.name] = name_span(argument.location, argument.name)
          end
          members = resolved.types.compact_map do |name, nested|
            constant = nested.as?(::Crystal::Const)
            next unless constant && constant.namespace == resolved
            value = constant.value.as?(::Crystal::NumberLiteral)
            next unless value
            IR::NIR::Enum::Member.new(name, value.value, source_members[name]?)
          end
          name = node.name.to_s
          IR::NIR::Enum.new(
            next_id,
            type,
            build_type(resolved.base_type.as(::Crystal::Type)),
            members,
            span(node),
            name_span(node.name.location, name)
          )
        end

        private def translate_path(node : ::Crystal::Path) : IR::NIR::Expr
          constant = node.target_const
          owner = constant.try(&.namespace)
          if constant && owner.is_a?(::Crystal::EnumType)
            type = build_type(owner)
            return IR::NIR::EnumMember.new(next_id, type, constant.name, type_of(node), span(node), path_name_span(node))
          end
          if constant
            return IR::NIR::ConstantReference.new(
              next_id,
              named_path(constant),
              type_of(node),
              span(node),
              path_name_span(node)
            )
          end
          unsupported(node)
        end

        private def definition_namespace_path(owner : ::Crystal::Type?) : Array(String)
          return [] of String unless owner
          resolved = owner.metaclass? ? owner.instance_type : owner
          resolved.is_a?(::Crystal::NonGenericModuleType) ? namespace_path(resolved) : [] of String
        end

        private def named_path(type : ::Crystal::NamedType) : Array(String)
          namespace_path(type.namespace) + [type.name]
        end

        private def namespace_path(type : ::Crystal::ModuleType) : Array(String)
          segments = [] of String
          current = type
          until current.is_a?(::Crystal::Program)
            segments << current.as(::Crystal::NamedType).name
            current = current.namespace
          end
          segments.reverse!
          segments
        end

        private def resolved_superclass_type(
          node : ::Crystal::ClassDef,
          resolved : ::Crystal::Type?,
        ) : IR::Type?
          return unless node.superclass
          superclass = case resolved
                       when ::Crystal::ClassType                then resolved.superclass
                       when ::Crystal::GenericClassInstanceType then resolved.superclass
                       end
          superclass.try { |type| build_type(type) }
        end

        private def translate_field_initializers(resolved : ::Crystal::Type?, fields : Array(IR::Field), owner_name : String) : Array(IR::NIR::FieldInitializer)
          return [] of IR::NIR::FieldInitializer unless resolved.is_a?(::Crystal::InstanceVarInitializerContainer)

          with_definition_context(DefinitionContext.new(owner_name)) do
            resolved.instance_vars_initializers.try do |initializers|
              initializers.compact_map do |initializer|
                name = initializer.name.lchop('@')
                field = fields.find { |candidate| candidate.name == name }
                next unless field

                value = translate_expr(initializer.value)
                IR::NIR::FieldInitializer.new(
                  next_id,
                  field,
                  value,
                  span(initializer.value),
                  name_span: declaration_name_span(initializer.value.location, name)
                )
              end
            end || [] of IR::NIR::FieldInitializer
          end
        end

        private def nil_return_restriction?(restriction : ::Crystal::ASTNode?) : Bool
          restriction.is_a?(::Crystal::Path) && restriction.names == ["Nil"]
        end

        private def register_owner_class(owner : ::Crystal::Type?, owner_type : IR::Type?) : Nil
          return unless owner && owner_type
          return if owner.is_a?(::Crystal::Program) || owner.metaclass?
          name = owner_type.name
          return unless name
          identity = owner_type.to_s
          return if (@state.class_names.includes?(name) && identity == name) || @state.owner_classes.has_key?(identity)
          return if name.in?("Array", "Hash", "Channel", "Mutex", "String", "Int32", "Bool", "Proc")
          return unless owner.is_a?(::Crystal::InstanceVarContainer)

          fields = owner.all_instance_vars.compact_map do |ivar_name, ivar|
            ivar.type?.try { |type| IR::Field.new(ivar_name.lchop('@'), build_type(type)) }
          end
          return if fields.empty?
          @state.owner_classes[identity] = IR::NIR::Class.new(next_id, name, nil, fields, nil, reference: !owner.struct?, concrete_type: owner_type)
        end

        # `T.new(args)` stays a structured reference in NIR: the class it
        # constructs and the range of the `T` token survive so tooling resolves
        # `T` to its declaration. Lowering commits the allocate/initialize/return
        # mechanism. Here the frontend only queues the `initialize` instance the
        # constructor will call (reached through Crystal's autogenerated `new`).
        private def translate_new(node : ::Crystal::Call) : IR::NIR::Expr
          owner_type = type_of(node)
          class_name = owner_type.try(&.name) || node.type?.try(&.to_s)
          return unsupported(node) unless class_name

          if builtin_exception?(class_name)
            return unsupported(node) if node.args.size > 1
            return IR::NIR::ExceptionNew.new(next_id, class_name, node.args.first?.try { |arg| translate_expr(arg) }, type_of(node), span(node))
          end

          initializer = queue_initialize(node)
          args = node.args.map_with_index do |arg, index|
            parameter_type = initializer.try do |definition|
              definition.args[index]?.try { |parameter| type_of(parameter) }
            end
            translate_constructor_arg(arg, parameter_type)
          end
          receiver_span = node.obj.try { |obj| name_span(obj.location, class_name) }
          owner_type ||= IR::Type.klass(class_name)
          IR::NIR::New.new(
            next_id,
            class_name,
            args,
            owner_type,
            span(node),
            name_span: receiver_span,
            method_site: method_site(node, owner_type, IR::NIR::CallableKind::Constructor),
            invokes_initializer: !initializer.nil?
          )
        end

        private def builtin_exception?(name : String) : Bool
          name.in?(
            "Exception", "OverflowError", "DivisionByZeroError", "ArgumentError",
            "KeyError", "TypeCastError", "IndexError", "Channel::ClosedError",
            "IO::Error", "File::Error", "File::NotFoundError", "File::AccessDeniedError"
          )
        end

        # Crystal applies contextual numeric-literal typing after selecting an
        # overload, but the argument AST node can retain its standalone type
        # (`10` remains Int32 while `initialize(Float64)` is selected). Preserve
        # the selected parameter type at the frontend boundary so call-edge
        # analysis consumes Crystal's answer instead of reconstructing it.
        private def translate_constructor_arg(node : ::Crystal::ASTNode, parameter_type : IR::Type?) : IR::NIR::Expr
          if node.is_a?(::Crystal::NumberLiteral) && parameter_type
            if parameter_type.family.float?
              return IR::NIR::FloatLiteral.new(next_id, node.value, parameter_type, span(node))
            elsif parameter_type.family.int?
              return IR::NIR::IntLiteral.new(next_id, node.value, parameter_type, span(node))
            end
          end

          translate_expr(node)
        end

        private def queue_initialize(node : ::Crystal::Call) : ::Crystal::Def?
          new_def = node.target_defs.try(&.first?)
          return unless new_def

          selected = nil
          collect_calls(new_def.body).each do |call|
            next unless call.name == "initialize"
            call.target_defs.try &.each do |target_def|
              next unless internal_def?(target_def)
              @state.queue(target_def)
              selected ||= target_def
            end
          end
          selected
        end

        private def collect_calls(node : ::Crystal::ASTNode, into = [] of ::Crystal::Call) : Array(::Crystal::Call)
          into << node if node.is_a?(::Crystal::Call)
          case node
          when ::Crystal::Expressions
            node.expressions.each { |child| collect_calls(child, into) }
          when ::Crystal::Assign
            collect_calls(node.value, into)
          end
          into
        end

        private def translate_block(node : ::Crystal::ASTNode) : IR::NIR::Block
          body = case node
                 when ::Crystal::Nop
                   [] of IR::NIR::Stmt
                 when ::Crystal::Expressions
                   translate_statements(node.expressions.reject(::Crystal::Nop))
                 else
                   translate_statements([node] of ::Crystal::ASTNode)
                 end
          IR::NIR::Block.new(next_id, body, span(node))
        end

        private def unsupported(node : ::Crystal::ASTNode) : IR::NIR::UnsupportedExpr
          IR::NIR::UnsupportedExpr.new(next_id, node.class.name, type_of(node), span(node))
        end

        # Crystal anchors a Rescue node at the `rescue` keyword rather than its
        # optional binding. Find that binding on the same source line so hover /
        # goto-definition cover `ex`, not the first two letters of `rescue`.
        private def rescue_name_span(node : ::Crystal::Rescue, name : String) : Source::Range?
          location = node.location
          return nil unless location && (source = source_file(location))

          line = location.line_number
          start = source.line_index.line_starts[line - 1]?
          return nil unless start
          finish = source.line_index.line_starts[line]? || source.code.bytesize
          source_line = source.code.byte_slice(start, finish - start)
          column = source.byte_column_at(line, location.column_number)
          index = source_line.index(name, column - 1)
          return nil unless index

          source.range_at(line, index + 1, name.bytesize)
        end

        private def next_id : NodeId
          @state.ids.next
        end

        private def with_definition_context(context : DefinitionContext, & : -> T) : T forall T
          saved_context = @context
          begin
            @context = context
            yield
          ensure
            @context = saved_context
          end
        end
      end
    end
  end
end
