module Tango
  module Lowering
    class ToLIR
      include CardinalityLowering
      include SemanticCollectionLowering
      include CapabilityLowering
      include ArrayLowering
      include StringLowering
      include HashLowering
      include ExceptionLowering
      include ConcurrencyLowering
      include CallLowering

      private class ConstructorRegistry
        @constructors = {} of String => Planning::Plans::Constructor
        @order = [] of String

        def register(constructor : Planning::Plans::Constructor) : Nil
          @order << constructor.name unless @constructors.has_key?(constructor.name)
          @constructors[constructor.name] = constructor
        end

        def each(& : Planning::Plans::Constructor ->) : Nil
          index = 0
          while name = @order[index]?
            yield @constructors[name]
            index += 1
          end
        end
      end

      private class LoweringContext
        getter declared : Set(String)
        getter declared_types : Hash(String, IR::Type)
        getter def_block_mode : Planning::Plans::BlockMode
        getter closure_mode : Planning::Plans::BlockMode
        getter return_type : IR::Type?

        def initialize(
          @declared = Set(String).new,
          @declared_types = {} of String => IR::Type,
          @def_block_mode = Planning::Plans::BlockMode::Plain,
          @closure_mode = Planning::Plans::BlockMode::Plain,
          @return_type : IR::Type? = nil,
        )
        end

        def child(closure_mode : Planning::Plans::BlockMode = @closure_mode) : self
          self.class.new(@declared.dup, @declared_types.dup, @def_block_mode, closure_mode, @return_type)
        end

        def declare(name : String, type : IR::Type? = nil) : Nil
          @declared << name
          type.try { |value| @declared_types[name] = value if value.union? }
        end
      end

      def self.translate(program : IR::NIR::Program, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Program
        new.translate(program, facts, plans)
      end

      def initialize
        @constructor_registry = ConstructorRegistry.new
        @classes = {} of String => IR::NIR::Class
        @context = LoweringContext.new
      end

      def translate(program : IR::NIR::Program, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Program
        functions = [] of IR::LIR::Func
        function_names = Set(String).new
        types = [] of IR::LIR::StructType
        enums = [] of IR::LIR::EnumType
        body = [] of IR::LIR::Stmt

        program.body.each do |stmt|
          case stmt
          when IR::NIR::Def
            # Crystal may surface several typed Def objects for repeated calls
            # to one concrete yield specialization. Planning gives all of them
            # the same signature-keyed function identity; lowering commits that
            # identity once so the target never receives duplicate declarations.
            name = plans.monomorphs[stmt.id]?.try(&.name)
            next if name && !function_names.add?(name)

            functions << lower_def(stmt, facts, plans)
          when IR::NIR::Class
            @classes[stmt.layout_identity] = stmt
            types << lower_class(stmt, plans)
          when IR::NIR::Enum
            enums << lower_enum(stmt, plans)
          else
            body << lower_stmt(stmt, facts, plans)
          end
        end

        # `.new` sites registered a constructor as they were lowered; mint one
        # func per distinct constructor. This is the allocate/initialize/return
        # mechanism committed as a single reusable lowering.
        @constructor_registry.each { |constructor| functions << build_constructor(constructor, facts, plans) }

        # Hoist one carrier struct decl per tagged-union representation. The
        # pointer-nilable arm needs no decl — it rides `*T` + Go nil.
        unions = plans.reprs.compact_map do |type, repr|
          repr.is_a?(Planning::Plans::CarrierRepr) ? build_union_type(type, repr) : nil
        end

        conversion_plans = {} of String => Planning::Plans::CarrierConversion
        plans.carrier_conversions.each_value { |plan| conversion_plans[plan.mapping.name] = plan }
        conversions = conversion_plans.values.map { |plan| build_union_conversion(plan) }

        arrays = plans.arrays.values.map do |repr|
          IR::LIR::ArrayType.new(repr.type, repr.element, repr.reference?)
        end

        hashes = plans.hashes.values.map do |repr|
          IR::LIR::HashType.new(repr.type, repr.reference?, repr.ordered?)
        end

        uncaught_exception = plans.uncaught_exception || raise "missing uncaught exception plan"
        IR::LIR::Program.new(body, functions, types, unions, arrays, hashes, facts.external_types.values, conversions, uncaught_exception, enums)
      end

      private def lower_enum(node : IR::NIR::Enum, plans : Planning::Plans::Table) : IR::LIR::EnumType
        plan = plans.enums[node.type]
        members = plan.members.map do |member|
          IR::LIR::EnumType::Member.new(member.name, member.value, member.target_name)
        end
        IR::LIR::EnumType.new(plan.type, plan.target_name, plan.base_type, members)
      end

      private def build_union_type(type : IR::Type, repr : Planning::Plans::CarrierRepr) : IR::LIR::UnionType
        variants = repr.variants.map { |variant| IR::LIR::UnionType::Variant.new(variant.label, variant.tag, variant.payload) }
        IR::LIR::UnionType.new(type, repr.name, variants)
      end

      private def build_union_conversion(plan : Planning::Plans::CarrierConversion) : IR::LIR::UnionConversion
        variants = plan.mapping.variants.map do |variant|
          IR::CarrierConversionMap::Variant.new(
            variant.member,
            variant.source_tag,
            variant.target_tag,
            variant.source_label,
            variant.target_label
          )
        end
        mapping = IR::CarrierConversionMap.new(
          plan.mapping.name,
          plan.mapping.source_name,
          plan.mapping.target_name,
          variants
        )
        IR::LIR::UnionConversion.new(plan.source, plan.target, mapping)
      end

      private def build_constructor(constructor : Planning::Plans::Constructor, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Func
        params = constructor.param_types.map_with_index { |type, index| IR::LIR::Param.new("a#{index}", type) }

        receiver = IR::LIR::Temp.new("self").as(IR::LIR::Value)
        init_args = [constructor.reference? ? receiver : IR::LIR::AddressOf.new(receiver).as(IR::LIR::Value)]
        constructor.param_types.each_index { |index| init_args << IR::LIR::Temp.new("a#{index}") }

        body = [IR::LIR::Assign.new("self", IR::LIR::Alloc.new(constructor.type), IR::LIR::Assign::Mode::Declare)] of IR::LIR::Stmt
        if klass = @classes[constructor.type.to_s]?
          context = LoweringContext.new
          context.declare("self", constructor.type)
          initializers = with_lowering_context(context) do
            klass.initializers.map do |initializer|
              IR::LIR::FieldAssign.new(
                receiver,
                initializer.name,
                lower_operand(initializer.value, initializer.type, facts, plans),
                loc(initializer.span)
              ).as(IR::LIR::Stmt)
            end
          end
          body.concat(initializers)
        end
        constructor.initialize_name.try do |name|
          body << IR::LIR::Discard.new(IR::LIR::Call.new(name, init_args))
        end
        body << lower_exit(IR::LIR::Temp.new("self"))

        IR::LIR::Func.new(constructor.name, params, constructor.type, body)
      end

      private def lower_class(node : IR::NIR::Class, plans : Planning::Plans::Table) : IR::LIR::StructType
        layout = plans.layouts[node.layout_identity]
        fields = layout.fields.dup
        IR::LIR::StructType.new(Planning::Mangle.sanitize(node.layout_identity), fields, layout.reference, layout.exception_ancestors, layout.identity_padding?, node.concrete_type)
      end

      private def lower_def(node : IR::NIR::Def, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Func
        commit_capability_dispatch(node, facts, plans)
        params = node.params.map_with_index do |param, index|
          IR::LIR::Param.new(
            param.name,
            param.type,
            by_ref: value_initializer_receiver?(node, index, plans),
            repr: exception_param_repr(node, param, index, plans)
          )
        end
        def_plan = plans.monomorphs[node.id]?
        block_mode = def_plan.try(&.block_mode) || Planning::Plans::BlockMode::Plain
        node.block_param.try do |block_param|
          params << IR::LIR::Param.new(block_param.name, nil, lir_proc_signature(block_param.signature, block_mode))
        end

        context = LoweringContext.new(def_block_mode: block_mode, return_type: node.return_type)
        node.params.each { |param| context.declare(param.name, param.type) }
        node.block_param.try { |block_param| context.declare(block_param.name) }
        body = with_lowering_context(context) do
          lower_def_body(node, facts, plans)
        end

        name = def_plan.try(&.name) || node.name
        IR::LIR::Func.new(name, params, node.return_type, body, loc(node.span))
      end

      private def value_initializer_receiver?(node : IR::NIR::Def, index : Int32, plans : Planning::Plans::Table) : Bool
        return false unless index == 0 && node.callable_kind.initializer?
        owner = node.owner
        return false unless owner
        layout = plans.layouts[owner.to_s]? || owner.name.try { |name| plans.layouts[name]? }
        !layout.nil? && !layout.reference
      end

      private def exception_param_repr(node : IR::NIR::Def, param : IR::NIR::Param, index : Int32, plans : Planning::Plans::Table) : IR::LIR::Param::Repr
        type = param.type
        layout = type.try { |value| plans.layouts[value.to_s]? || value.name.try { |name| plans.layouts[name]? } }
        return IR::LIR::Param::Repr::Native unless layout.try(&.exception_runtime?)

        receiver = index == 0 && !node.owner.nil? && (node.callable_kind.instance_method? || node.callable_kind.initializer?)
        receiver ? IR::LIR::Param::Repr::Native : IR::LIR::Param::Repr::ExceptionInterface
      end

      private def lir_proc_signature(signature : IR::ProcSignature, mode : Planning::Plans::BlockMode = Planning::Plans::BlockMode::Plain) : IR::ProcSignature
        return_type = mode.protocol? ? IR::Type.bool : signature.return_type
        IR::ProcSignature.new(signature.param_types, return_type)
      end

      private def lower_def_body(node : IR::NIR::Def, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : Array(IR::LIR::Stmt)
        return_type = node.return_type
        returns = return_type ? !return_type.nil_type? : false
        stmts = node.body.body

        stmts.map_with_index do |stmt, index|
          if returns && index == stmts.size - 1 && stmt.is_a?(IR::NIR::Expr) && !(stmt.is_a?(IR::NIR::ExceptionHandler) && no_return?(stmt.type))
            lower_exit(lower_operand(stmt, return_type, facts, plans), loc(stmt.span))
          else
            lower_stmt(stmt, facts, plans)
          end
        end
      end

      private def lower_exit(value : IR::LIR::Value?, loc : IR::LIR::SourceLoc? = nil, shape : IR::LIR::AbruptExit::Shape = IR::LIR::AbruptExit::Shape::Return, target : String? = nil) : IR::LIR::Stmt
        IR::LIR::AbruptExit.new(shape, value, loc, target)
      end

      private def lower_block_literal(node : IR::NIR::BlockLiteral, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        mode = plans.closures[node.id]?.try(&.mode) || Planning::Plans::BlockMode::Plain
        params = node.args.map_with_index do |arg, index|
          IR::LIR::Param.new(arg.name, node.signature.param_types[index]?)
        end
        return_type = mode.protocol? ? IR::Type.bool : node.signature.return_type

        context = @context.child(closure_mode: mode)
        node.args.each_with_index do |arg, index|
          context.declare(arg.name, node.signature.param_types[index]?)
        end
        body = with_lowering_context(context) do
          lower_closure_body(node.body, return_type, facts, plans, mode)
        end

        IR::LIR::Closure.new(params, return_type, body)
      end

      private def lower_closure_body(block : IR::NIR::Block, return_type : IR::Type?, facts : Analysis::Facts::Table, plans : Planning::Plans::Table, mode : Planning::Plans::BlockMode) : Array(IR::LIR::Stmt)
        if mode.protocol?
          body = block.body.map { |stmt| lower_stmt(stmt, facts, plans) }
          last = block.body.last?
          body << lower_exit(IR::LIR::BoolConst.new(false)) unless protocol_terminal?(last)
          return body
        end

        returns = return_type ? !return_type.nil_type? : false
        stmts = block.body

        stmts.map_with_index do |stmt, index|
          if returns && index == stmts.size - 1 && stmt.is_a?(IR::NIR::Expr)
            lower_exit(lower_operand(stmt, return_type, facts, plans), loc(stmt.span))
          else
            lower_stmt(stmt, facts, plans)
          end
        end
      end

      private def lower_invoke_block(node : IR::NIR::InvokeBlock, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        callee = lower_value(node.receiver, facts, plans)
        args = node.args.map { |arg| lower_value(arg, facts, plans) }
        IR::LIR::InvokeClosure.new(callee, args)
      end

      # A protocol block's boolean return is only needed on its ordinary
      # fallthrough path. A bare block `break`/`next` has already lowered to a
      # terminal protocol return; appending `return false` after it makes Go's
      # vet pass reject the unreachable line. Loop-targeted exits still need a
      # fallthrough value once their surrounding loop completes.
      private def protocol_terminal?(stmt : IR::NIR::Stmt?) : Bool
        return true if stmt.is_a?(IR::NIR::Expr) && no_return?(stmt.type)
        return true if stmt.is_a?(IR::NIR::Break) && stmt.target.nil?
        return true if stmt.is_a?(IR::NIR::Next) && stmt.target.nil?

        false
      end

      # Lowering stays conservative and shape-aware: it dispatches on the
      # nodes it can commit, and everything else falls through to an
      # unsupported LIR node. Lowering owns traversal and statement order, so
      # generic Walk recursion is intentionally not used here.
      private def lower_stmt(stmt : IR::NIR::Stmt, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Stmt
        case stmt
        when IR::NIR::Call
          if stmt.primitive
            IR::LIR::Discard.new(lower_value(stmt, facts, plans), loc(stmt.span))
          else
            case plan = plans.calls[stmt.id]?
            when Planning::Plans::ExternalGo
              args = stmt.args.map { |arg| lower_value(arg, facts, plans) }
              IR::LIR::ExternalCall.new(lower_external_target(plan.callee), args, loc(stmt.span))
            when Planning::Plans::InternalCall
              IR::LIR::Discard.new(lower_internal_call(stmt, plan, facts, plans), loc(stmt.span))
            else
              IR::LIR::UnsupportedStmt.new("unsupported call #{stmt.name}", loc(stmt.span))
            end
          end
        when IR::NIR::SemanticCollectionOperation
          IR::LIR::Discard.new(lower_semantic_collection(stmt, facts, plans), loc(stmt.span))
        when IR::NIR::IndexedOperation
          IR::LIR::Discard.new(lower_call_value(stmt.fallback, facts, plans), loc(stmt.span))
        when IR::NIR::Assign
          lower_assign(stmt, facts, plans)
        when IR::NIR::If
          lower_if(stmt, facts, plans)
        when IR::NIR::While
          lower_while(stmt, facts, plans)
        when IR::NIR::Spawn
          IR::LIR::Spawn.new(lower_value(stmt.proc, facts, plans), loc(stmt.span))
        when IR::NIR::StringEachChar
          lower_string_each_char(stmt, facts, plans)
        when IR::NIR::ChannelOp
          lower_channel_op_stmt(stmt, facts, plans)
        when IR::NIR::Select
          lower_select(stmt, facts, plans)
        when IR::NIR::ExceptionHandler
          lower_handler(stmt, facts, plans)
        when IR::NIR::Raise
          shape = stmt.kind.message? ? IR::LIR::AbruptExit::Shape::RaiseMessage : IR::LIR::AbruptExit::Shape::RaiseException
          lower_exit(lower_value(stmt.value, facts, plans), loc(stmt.span), shape: shape)
        when IR::NIR::Return
          lower_exit(stmt.value.try { |value| lower_operand(value, @context.return_type, facts, plans) }, loc(stmt.span))
        when IR::NIR::Break
          if stmt.target.nil? && @context.closure_mode.protocol?
            lower_exit(IR::LIR::BoolConst.new(true), loc(stmt.span))
          elsif stmt.target.nil? && @context.closure_mode.value?
            IR::LIR::UnsupportedStmt.new("break out of a value-returning block needs union-typed block lowering", loc(stmt.span))
          else
            lower_exit(stmt.value.try { |value| lower_value(value, facts, plans) }, loc(stmt.span), shape: IR::LIR::AbruptExit::Shape::Break, target: stmt.target.try(&.to_s))
          end
        when IR::NIR::Next
          if stmt.target.nil? && @context.closure_mode.protocol?
            lower_exit(IR::LIR::BoolConst.new(false), loc(stmt.span))
          elsif stmt.target.nil? && @context.closure_mode.value?
            lower_exit(stmt.value.try { |value| lower_value(value, facts, plans) }, loc(stmt.span))
          elsif stmt.target.nil?
            lower_exit(nil, loc(stmt.span))
          else
            lower_exit(stmt.value.try { |value| lower_value(value, facts, plans) }, loc(stmt.span), shape: IR::LIR::AbruptExit::Shape::Next, target: stmt.target.try(&.to_s))
          end
        when IR::NIR::InvokeBlock
          if stmt.yield_site? && @context.def_block_mode.protocol?
            IR::LIR::If.new(
              lower_invoke_block(stmt, facts, plans),
              [lower_exit(nil)] of IR::LIR::Stmt,
              [] of IR::LIR::Stmt,
              loc(stmt.span)
            )
          else
            IR::LIR::Discard.new(lower_value(stmt, facts, plans), loc(stmt.span))
          end
        when IR::NIR::Local, IR::NIR::Literal, IR::NIR::EnumMember, IR::NIR::Interpolation, IR::NIR::StringSplit, IR::NIR::Size, IR::NIR::StringCharAt, IR::NIR::StringToFloat, IR::NIR::StringToInteger, IR::NIR::New, IR::NIR::ChannelNew, IR::NIR::MutexNew,
             IR::NIR::ArrayNew, IR::NIR::ArrayBuild, IR::NIR::ArrayGet, IR::NIR::ArraySet, IR::NIR::ArrayPush,
             IR::NIR::HashNew, IR::NIR::HashGet, IR::NIR::HashSet, IR::NIR::HashFetch, IR::NIR::HashHasKey, IR::NIR::HashKeyAt,
             IR::NIR::Not, IR::NIR::TypeTest, IR::NIR::Cast
          IR::LIR::Discard.new(lower_value(stmt, facts, plans), loc(stmt.span))
        else
          IR::LIR::UnsupportedStmt.new("unsupported statement #{stmt.class.name}", loc(stmt.span))
        end
      end

      private def lower_block(block : IR::NIR::Block, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : Array(IR::LIR::Stmt)
        block.body.map { |stmt| lower_stmt(stmt, facts, plans) }
      end

      private def lower_if(stmt : IR::NIR::If, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Stmt
        else_body = stmt.else_branch.try { |branch| lower_block(branch, facts, plans) } || [] of IR::LIR::Stmt
        IR::LIR::If.new(lower_cond(stmt.cond, facts, plans), lower_block(stmt.then_branch, facts, plans), else_body, loc(stmt.span))
      end

      private def lower_while(stmt : IR::NIR::While, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Stmt
        IR::LIR::While.new(lower_cond(stmt.cond, facts, plans), lower_block(stmt.body, facts, plans), loc(stmt.span), stmt.id.to_s)
      end

      private def lower_cond(node : IR::NIR::Expr, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        value = lower_value(node, facts, plans)
        type = node.type

        return IR::LIR::UnsupportedValue.new("condition has no resolved type", loc(node.span)) unless type
        return value if type.family.bool?
        return IR::LIR::BoolConst.new(false) if type.nil_type?

        if type.union? && type.members.any?(&.family.bool?)
          IR::LIR::UnsupportedValue.new("truthiness for a union containing Bool needs carrier-aware lowering", loc(node.span))
        elsif type.nilable?
          IR::LIR::NilCheck.new(value, type)
        else
          IR::LIR::BoolConst.new(true)
        end
      end

      # Commits box/nil-conversion for a value flowing into an expected slot: a
      # member value crossing into a union slot is boxed (carrier) or spelled as
      # a bare pointer / Go nil. A value already the slot's type passes
      # through. Compares structured types — no cross-phase side-channel.
      private def lower_operand(node : IR::NIR::Expr, expected : IR::Type?, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        return lower_value(node, facts, plans) unless expected && expected.union? && node.type != expected

        source = node.type
        if source && source.union?
          if conversion = plans.carrier_conversions[node.id]?
            return IR::LIR::Widen.new(lower_value(node, facts, plans), source, expected, conversion.mapping.name)
          end
          return IR::LIR::UnsupportedValue.new("unplanned union conversion #{source} -> #{expected}", loc(node.span))
        end

        case plans.reprs[expected]?
        when Planning::Plans::PointerRepr
          # nil -> Go nil; a reference value is already a *T, so identity.
          node.is_a?(IR::NIR::NilLiteral) ? IR::LIR::NilConst.new : lower_value(node, facts, plans)
        when Planning::Plans::CarrierRepr
          if node.is_a?(IR::NIR::NilLiteral)
            IR::LIR::Box.new(nil, expected, nil)
          else
            IR::LIR::Box.new(lower_value(node, facts, plans), expected, node.type)
          end
        else
          lower_value(node, facts, plans)
        end
      end

      private def lower_assign(stmt : IR::NIR::Assign, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Stmt
        target = stmt.target
        if target.is_a?(IR::NIR::InstanceVar)
          IR::LIR::FieldAssign.new(IR::LIR::Temp.new("self"), target.name, lower_value(stmt.value, facts, plans), loc(stmt.span))
        elsif target.is_a?(IR::NIR::Local)
          if facts.unread_local_writes.includes?(target.id)
            # Analysis proved this local's value is never read. Keep all
            # right-hand-side effects, but commit the Go-safe discard shape
            # rather than creating a slot Go would reject as unused.
            return IR::LIR::Discard.new(lower_operand(stmt.value, target.type, facts, plans), loc(stmt.span))
          end

          name = target.name
          mode = @context.declared.includes?(name) ? IR::LIR::Assign::Mode::Reassign : IR::LIR::Assign::Mode::Declare
          @context.declare(name, target.type)

          IR::LIR::Assign.new(name, lower_operand(stmt.value, target.type, facts, plans), mode, loc(stmt.span))
        else
          IR::LIR::UnsupportedStmt.new("unsupported assignment target #{target.class.name}", loc(stmt.span))
        end
      end

      private def lower_value(stmt : IR::NIR::Stmt, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        case stmt
        when IR::NIR::IntLiteral
          type = stmt.type
          if type && type.family.int?
            IR::LIR::IntConst.new(stmt.value, type)
          else
            IR::LIR::UnsupportedValue.new("integer literal has no resolved integer type", loc(stmt.span))
          end
        when IR::NIR::FloatLiteral
          type = stmt.type
          if type && type.family.float?
            IR::LIR::FloatConst.new(stmt.value, type)
          else
            IR::LIR::UnsupportedValue.new("float literal has no resolved float type", loc(stmt.span))
          end
        when IR::NIR::StringLiteral
          IR::LIR::StringConst.new(stmt.value)
        when IR::NIR::EnumMember
          IR::LIR::EnumConst.new(stmt.enum_type, stmt.name)
        when IR::NIR::Interpolation
          lower_interpolation(stmt, facts, plans)
        when IR::NIR::StringSplit
          lower_string_split(stmt, facts, plans)
        when IR::NIR::Size
          lower_size(stmt, facts, plans)
        when IR::NIR::StringCharAt
          lower_string_char_at(stmt, facts, plans)
        when IR::NIR::StringToFloat
          lower_string_to_float(stmt, facts, plans)
        when IR::NIR::StringToInteger
          lower_string_to_integer(stmt, facts, plans)
        when IR::NIR::StringEachChar
          lower_string_each_char_value(stmt, facts, plans)
        when IR::NIR::BoolLiteral
          IR::LIR::BoolConst.new(stmt.value)
        when IR::NIR::NilLiteral
          # A bare `nil` whose slot type is itself `Nil` (a union slot is boxed
          # or Go-nil'd in lower_operand first). The standalone `tangoNil{}` unit.
          IR::LIR::NilValue.new
        when IR::NIR::Local
          lower_local_read(stmt, plans)
        when IR::NIR::InstanceVar
          IR::LIR::FieldAccess.new(IR::LIR::Temp.new("self"), stmt.name)
        when IR::NIR::New
          lower_new(stmt, facts, plans)
        when IR::NIR::ExceptionNew
          IR::LIR::ExceptionValue.new(stmt.class_name, stmt.message.try { |message| lower_value(message, facts, plans) })
        when IR::NIR::Call
          lower_call_value(stmt, facts, plans)
        when IR::NIR::SemanticCollectionOperation
          lower_semantic_collection(stmt, facts, plans)
        when IR::NIR::IndexedOperation
          lower_call_value(stmt.fallback, facts, plans)
        when IR::NIR::InvokeBlock
          lower_invoke_block(stmt, facts, plans)
        when IR::NIR::BlockLiteral
          lower_block_literal(stmt, facts, plans)
        when IR::NIR::If
          lower_if_value(stmt, facts, plans)
        when IR::NIR::ExceptionHandler
          lower_handler_value(stmt, facts, plans)
        when IR::NIR::ChannelNew
          IR::LIR::MakeChan.new(stmt.element, stmt.capacity.try { |capacity| lower_value(capacity, facts, plans) })
        when IR::NIR::MutexNew
          stmt.type.try { |type| IR::LIR::MakeMutex.new(type) } || IR::LIR::UnsupportedValue.new("Mutex.new has no resolved type", loc(stmt.span))
        when IR::NIR::ArrayNew
          lower_array_new(stmt, plans)
        when IR::NIR::ArrayBuild
          lower_array_build(stmt, facts, plans)
        when IR::NIR::ArrayGet
          lower_array_get(stmt, facts, plans)
        when IR::NIR::ArraySet
          lower_array_set(stmt, facts, plans)
        when IR::NIR::ArrayPush
          lower_array_push(stmt, facts, plans)
        when IR::NIR::HashNew
          lower_hash_new(stmt, facts, plans)
        when IR::NIR::HashGet
          lower_hash_get(stmt, facts, plans)
        when IR::NIR::HashSet
          lower_hash_set(stmt, facts, plans)
        when IR::NIR::HashFetch
          lower_hash_fetch(stmt, facts, plans)
        when IR::NIR::HashHasKey
          lower_hash_has_key(stmt, facts, plans)
        when IR::NIR::HashKeyAt
          lower_hash_key_at(stmt, facts, plans)
        when IR::NIR::Not
          IR::LIR::Not.new(lower_value(stmt.value, facts, plans))
        when IR::NIR::TypeTest
          lower_type_test(stmt, facts, plans)
        when IR::NIR::Cast
          lower_cast(stmt, facts, plans)
        when IR::NIR::ValueSequence
          lower_value_sequence(stmt, facts, plans)
        when IR::NIR::ChannelOp
          lower_channel_op_value(stmt, facts, plans)
        else
          IR::LIR::UnsupportedValue.new("unsupported value #{stmt.class.name}", loc(stmt.span))
        end
      end

      private def lower_value_sequence(node : IR::NIR::ValueSequence, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        type = node.type || IR::Type.unknown
        with_lowering_context(@context.child) do
          body = lower_block(node.prefix, facts, plans)
          value = lower_operand(node.value, type, facts, plans)
          IR::LIR::ValueSequence.new(body, value, type)
        end
      end

      private def lower_type_test(node : IR::NIR::TypeTest, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        plan = plans.type_tests[node.id]?
        return IR::LIR::UnsupportedValue.new("unplanned type test #{node.value.type} is_a? #{node.target}", loc(node.span)) unless plan
        strategy = case plan.strategy
                   in .static_true?     then IR::LIR::TypeTest::Strategy::StaticTrue
                   in .static_false?    then IR::LIR::TypeTest::Strategy::StaticFalse
                   in .pointer_non_nil? then IR::LIR::TypeTest::Strategy::PointerNonNil
                   in .pointer_nil?     then IR::LIR::TypeTest::Strategy::PointerNil
                   in .carrier_tag?     then IR::LIR::TypeTest::Strategy::CarrierTag
                   in .carrier_nil?     then IR::LIR::TypeTest::Strategy::CarrierNil
                   end
        IR::LIR::TypeTest.new(lower_value(node.value, facts, plans), plan.source, plan.target, strategy)
      end

      private def lower_cast(node : IR::NIR::Cast, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        plan = plans.casts[node.id]?
        return IR::LIR::UnsupportedValue.new("cast from #{node.value.type} to #{node.target} is not supported", loc(node.span)) unless plan
        strategy = case plan.strategy
                   in .passthrough?     then IR::LIR::Cast::Strategy::Passthrough
                   in .pointer_checked? then IR::LIR::Cast::Strategy::PointerChecked
                   in .carrier_checked? then IR::LIR::Cast::Strategy::CarrierChecked
                   end
        IR::LIR::Cast.new(lower_value(node.value, facts, plans), plan.source, plan.target, strategy, loc(node.span))
      end

      # A local read narrowed below its declared union slot is unboxed: the
      # carrier's active payload (`x.v<label>`), or identity for a pointer-repr
      # slot (the `*T` already is the value). The full-union read (cond site)
      # keeps its carrier, so a following NilCheck can inspect the tag.
      private def lower_local_read(node : IR::NIR::Local, plans : Planning::Plans::Table) : IR::LIR::Value
        temp = IR::LIR::Temp.new(node.name)
        declared = @context.declared_types[node.name]?
        occurrence = node.type
        return temp unless declared && occurrence && !occurrence.union? && declared.union?

        case plans.reprs[declared]?
        when Planning::Plans::CarrierRepr
          IR::LIR::Unbox.new(temp, declared, occurrence)
        else
          temp
        end
      end

      private def lower_new(stmt : IR::NIR::New, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        constructor = plans.constructors[stmt.id]?
        return IR::LIR::UnsupportedValue.new("unplanned constructor #{stmt.class_name}", loc(stmt.span)) unless constructor

        @constructor_registry.register(constructor)
        args = stmt.args.map { |arg| lower_value(arg, facts, plans) }
        IR::LIR::Call.new(constructor.name, args)
      end

      private def lower_interpolation(stmt : IR::NIR::Interpolation, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        pieces = stmt.pieces.map do |piece|
          plan = plans.scalar_stringifications[piece.id]?
          unless plan
            return IR::LIR::UnsupportedValue.new("cannot interpolate non-scalar #{piece.type || "?"}", loc(piece.span || stmt.span))
          end
          if plan.presentation == IR::ScalarPresentation::Nil
            IR::LIR::ScalarStringify.new(nil, [lower_stmt(piece, facts, plans)] of IR::LIR::Stmt, plan.type, plan.presentation)
          else
            IR::LIR::ScalarStringify.new(lower_value(piece, facts, plans), [] of IR::LIR::Stmt, plan.type, plan.presentation)
          end
        end
        IR::LIR::Interpolation.new(pieces)
      end

      private def with_lowering_context(context : LoweringContext, & : -> T) : T forall T
        saved_context = @context
        begin
          @context = context
          yield
        ensure
          @context = saved_context
        end
      end

      private def lower_if_value(stmt : IR::NIR::If, facts : Analysis::Facts::Table, plans : Planning::Plans::Table) : IR::LIR::Value
        else_branch = stmt.else_branch
        return IR::LIR::UnsupportedValue.new("unsupported if value without else", loc(stmt.span)) unless else_branch

        then_value = block_value(stmt.then_branch)
        else_value = block_value(else_branch)
        return IR::LIR::UnsupportedValue.new("unsupported multi-statement if value", loc(stmt.span)) unless then_value && else_value

        # Each arm crosses into the if-expression's own (possibly union) type, so
        # a narrower arm value is boxed here — the box-per-branch site.
        IR::LIR::IfValue.new(
          lower_cond(stmt.cond, facts, plans),
          lower_operand(then_value, stmt.type, facts, plans),
          lower_operand(else_value, stmt.type, facts, plans),
          stmt.type
        )
      end

      private def block_value(block : IR::NIR::Block) : IR::NIR::Expr?
        return nil unless block.body.size == 1

        block.body.first.as?(IR::NIR::Expr)
      end

      private def loc(span : Source::Range?) : IR::LIR::SourceLoc?
        return nil unless span
        line = span.line
        column = span.column
        return nil unless line && column

        IR::LIR::SourceLoc.new(span.path, line, column)
      end
    end
  end
end
