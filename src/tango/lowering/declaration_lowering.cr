module Tango
  module Lowering
    # Declaration and representation commitments produced while ToLIR assembles
    # a program. Expression and statement dispatch remain in the coordinator.
    class ToLIR
      private def declarations(nodes : Array(IR::NIR::Stmt), into = [] of IR::NIR::Stmt) : Array(IR::NIR::Stmt)
        nodes.each do |node|
          into << node
          if namespace = node.as?(IR::NIR::Namespace)
            declarations(namespace.body.body, into)
          end
        end
        into
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
    end
  end
end
