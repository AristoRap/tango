module Tango
  module Expansion
    # Runs target-neutral semantic expansion over the complete frontend-owned
    # NIR graph. Frontends only normalize resolved calls and their annotations;
    # the core owns when those calls become language semantic operations.
    class Driver
      def self.run(program : IR::NIR::Program) : IR::NIR::Program
        new.run(program)
      end

      def run(program : IR::NIR::Program) : IR::NIR::Program
        IR::NIR::Program.new(
          program.body.map { |node| rewrite(node) },
          program.type_annotations
        )
      end

      private def rewrite(node : IR::NIR::Stmt) : IR::NIR::Stmt
        case node
        when IR::NIR::Block
          rewrite_block(node)
        when IR::NIR::Assign
          value = rewrite_expr(node.value)
          case target = node.target
          when IR::NIR::Local
            IR::NIR::Assign.new(node.id, target, value, node.type, node.span)
          when IR::NIR::InstanceVar
            IR::NIR::Assign.new(node.id, target, value, node.type, node.span)
          else
            raise ArgumentError.new("unhandled assignment target: #{target.class.name}")
          end
        when IR::NIR::If
          IR::NIR::If.new(
            node.id,
            rewrite_expr(node.cond),
            rewrite_block(node.then_branch),
            node.else_branch.try { |branch| rewrite_block(branch) },
            node.type,
            node.span
          )
        when IR::NIR::While
          IR::NIR::While.new(node.id, rewrite_expr(node.cond), rewrite_block(node.body), node.span)
        when IR::NIR::Return
          IR::NIR::Return.new(node.id, node.value.try { |value| rewrite_expr(value) }, node.target, node.span)
        when IR::NIR::Break
          IR::NIR::Break.new(node.id, node.value.try { |value| rewrite_expr(value) }, node.target, node.span)
        when IR::NIR::Next
          IR::NIR::Next.new(node.id, node.value.try { |value| rewrite_expr(value) }, node.target, node.span)
        when IR::NIR::Def
          IR::NIR::Def.new(
            node.id,
            node.name,
            node.params,
            rewrite_block(node.body),
            node.return_type,
            node.span,
            node.block_param,
            node.name_span,
            node.owner,
            node.callable_kind,
            node.capability_witnesses
          )
        when IR::NIR::Class
          initializers = node.initializers.map do |initializer|
            rewrite(initializer).as(IR::NIR::FieldInitializer)
          end
          IR::NIR::Class.new(
            node.id,
            node.name,
            node.superclass_name,
            node.fields,
            node.span,
            node.name_span,
            node.reference?,
            initializers,
            node.concrete_type,
            node.superclass_type
          )
        when IR::NIR::Enum
          node
        when IR::NIR::FieldInitializer
          IR::NIR::FieldInitializer.new(
            node.id,
            node.field,
            rewrite_expr(node.value),
            node.span,
            node.name_span
          )
        when IR::NIR::Expr
          rewrite_expr(node)
        when IR::NIR::Param, IR::NIR::BlockArg, IR::NIR::BlockParam
          node
        else
          raise ArgumentError.new("unhandled NIR node: #{node.class.name}")
        end
      end

      private def rewrite_block(node : IR::NIR::Block) : IR::NIR::Block
        IR::NIR::Block.new(node.id, node.body.map { |child| rewrite(child) }, node.span)
      end

      private def rewrite_expr(node : IR::NIR::Expr) : IR::NIR::Expr
        case node
        when IR::NIR::Call
          rewrite_call(node)
        when IR::NIR::CollectionMap
          IR::NIR::CollectionMap.new(rewrite_fallback(node.fallback))
        when IR::NIR::CollectionFilter
          IR::NIR::CollectionFilter.new(rewrite_fallback(node.fallback), node.mode)
        when IR::NIR::CollectionEach
          IR::NIR::CollectionEach.new(rewrite_fallback(node.fallback))
        when IR::NIR::CollectionFold
          IR::NIR::CollectionFold.new(rewrite_fallback(node.fallback))
        when IR::NIR::IndexedRead
          IR::NIR::IndexedRead.new(rewrite_fallback(node.fallback))
        when IR::NIR::IndexedWrite
          IR::NIR::IndexedWrite.new(rewrite_fallback(node.fallback))
        when IR::NIR::BlockLiteral
          IR::NIR::BlockLiteral.new(
            node.id,
            node.args,
            rewrite_block(node.body),
            node.signature,
            node.type,
            node.span
          )
        when IR::NIR::InvokeBlock
          IR::NIR::InvokeBlock.new(
            node.id,
            rewrite_expr(node.receiver),
            node.args.map { |arg| rewrite_expr(arg) },
            node.type,
            node.span,
            node.method_site,
            node.yield_site?
          )
        when IR::NIR::Assign
          rewrite(node).as(IR::NIR::Expr)
        when IR::NIR::If
          rewrite(node).as(IR::NIR::Expr)
        when IR::NIR::Interpolation
          IR::NIR::Interpolation.new(node.id, node.pieces.map { |piece| rewrite_expr(piece) }, node.type, node.span)
        when IR::NIR::StringSplit
          IR::NIR::StringSplit.new(
            node.id,
            rewrite_expr(node.string),
            node.type,
            node.span,
            node.separator.try { |separator| rewrite_expr(separator) },
            node.method_site
          )
        when IR::NIR::Size
          IR::NIR::Size.new(node.id, rewrite_expr(node.value), node.type, node.span, node.method_site)
        when IR::NIR::StringCharAt
          IR::NIR::StringCharAt.new(
            node.id,
            rewrite_expr(node.string),
            rewrite_expr(node.index),
            node.type,
            node.span,
            node.method_site
          )
        when IR::NIR::StringEachChar
          IR::NIR::StringEachChar.new(
            node.id,
            rewrite_expr(node.string),
            rewrite_expr(node.block).as(IR::NIR::BlockLiteral),
            node.type,
            node.span,
            node.method_site
          )
        when IR::NIR::StringToFloat
          IR::NIR::StringToFloat.new(node.id, rewrite_expr(node.string), node.type, node.span, node.method_site)
        when IR::NIR::StringToInteger
          IR::NIR::StringToInteger.new(
            node.id,
            rewrite_expr(node.string),
            node.options.map { |option| rewrite_expr(option) },
            node.type,
            node.span,
            node.method_site
          )
        when IR::NIR::Not
          IR::NIR::Not.new(node.id, rewrite_expr(node.value), node.type, node.span)
        when IR::NIR::TypeTest
          IR::NIR::TypeTest.new(node.id, rewrite_expr(node.value), node.target, node.type, node.span)
        when IR::NIR::Cast
          IR::NIR::Cast.new(node.id, rewrite_expr(node.value), node.target, node.type, node.span)
        when IR::NIR::HashGet
          IR::NIR::HashGet.new(node.id, rewrite_expr(node.hash), rewrite_expr(node.key), node.hash_type, node.type, node.span, node.method_site)
        when IR::NIR::HashSet
          IR::NIR::HashSet.new(node.id, rewrite_expr(node.hash), rewrite_expr(node.key), rewrite_expr(node.value), node.hash_type, node.type, node.span, node.method_site)
        when IR::NIR::HashFetch
          IR::NIR::HashFetch.new(node.id, rewrite_expr(node.hash), rewrite_expr(node.key), rewrite_expr(node.default), node.hash_type, node.type, node.span, node.method_site)
        when IR::NIR::HashHasKey
          IR::NIR::HashHasKey.new(node.id, rewrite_expr(node.hash), rewrite_expr(node.key), node.hash_type, node.type, node.span, node.method_site)
        when IR::NIR::HashKeyAt
          IR::NIR::HashKeyAt.new(node.id, rewrite_expr(node.hash), rewrite_expr(node.index), node.hash_type, node.type, node.span, node.method_site)
        when IR::NIR::ArrayBuild
          IR::NIR::ArrayBuild.new(node.id, node.element, rewrite_expr(node.size), node.type, node.span)
        when IR::NIR::ArrayGet
          IR::NIR::ArrayGet.new(node.id, rewrite_expr(node.array), rewrite_expr(node.index), node.element, node.type, node.span, node.method_site)
        when IR::NIR::ArraySet
          IR::NIR::ArraySet.new(node.id, rewrite_expr(node.array), rewrite_expr(node.index), rewrite_expr(node.value), node.element, node.type, node.span, node.method_site)
        when IR::NIR::ArrayPush
          IR::NIR::ArrayPush.new(node.id, rewrite_expr(node.array), rewrite_expr(node.value), node.element, node.type, node.span, node.method_site)
        when IR::NIR::ValueSequence
          IR::NIR::ValueSequence.new(node.id, rewrite_block(node.prefix), rewrite_expr(node.value), node.type, node.span)
        when IR::NIR::New
          IR::NIR::New.new(
            node.id,
            node.class_name,
            node.args.map { |arg| rewrite_expr(arg) },
            node.type,
            node.span,
            node.name_span,
            node.method_site,
            node.invokes_initializer?
          )
        when IR::NIR::Spawn
          IR::NIR::Spawn.new(node.id, rewrite_expr(node.proc), node.type, node.span)
        when IR::NIR::ChannelNew
          IR::NIR::ChannelNew.new(
            node.id,
            node.element,
            node.capacity.try { |capacity| rewrite_expr(capacity) },
            node.type,
            node.span
          )
        when IR::NIR::ChannelOp
          IR::NIR::ChannelOp.new(
            node.id,
            node.kind,
            rewrite_expr(node.channel),
            node.value.try { |value| rewrite_expr(value) },
            node.element,
            node.type,
            node.span,
            node.method_site
          )
        when IR::NIR::Select
          arms = node.arms.map do |arm|
            IR::NIR::Select::Arm.new(
              arm.kind,
              rewrite_expr(arm.channel),
              arm.value.try { |value| rewrite_expr(value) },
              arm.captured,
              arm.element,
              rewrite_block(arm.body)
            )
          end
          IR::NIR::Select.new(
            node.id,
            arms,
            node.else_body.try { |body| rewrite_block(body) },
            node.type,
            node.span
          )
        when IR::NIR::Raise
          IR::NIR::Raise.new(node.id, rewrite_expr(node.value), node.kind, node.type, node.span)
        when IR::NIR::ExceptionNew
          IR::NIR::ExceptionNew.new(
            node.id,
            node.class_name,
            node.message.try { |message| rewrite_expr(message) },
            node.type,
            node.span
          )
        when IR::NIR::ExceptionHandler
          clauses = node.clauses.map do |clause|
            IR::NIR::RescueClause.new(clause.types, clause.binding, rewrite_block(clause.body))
          end
          IR::NIR::ExceptionHandler.new(
            node.id,
            rewrite_block(node.body),
            clauses,
            node.else_branch.try { |branch| rewrite_block(branch) },
            node.ensure_branch.try { |branch| rewrite_block(branch) },
            node.type,
            node.span
          )
        when IR::NIR::IntLiteral, IR::NIR::FloatLiteral, IR::NIR::StringLiteral,
             IR::NIR::BoolLiteral, IR::NIR::NilLiteral, IR::NIR::Local,
             IR::NIR::ClassRef, IR::NIR::EnumMember, IR::NIR::InstanceVar, IR::NIR::ArrayNew,
             IR::NIR::HashNew, IR::NIR::MutexNew, IR::NIR::UnsupportedExpr
          node
        else
          raise ArgumentError.new("unhandled NIR expression: #{node.class.name}")
        end
      end

      private def rewrite_call(node : IR::NIR::Call) : IR::NIR::Expr
        SemanticCalls.expand(rewrite_fallback(node))
      end

      private def rewrite_fallback(node : IR::NIR::Call) : IR::NIR::Call
        IR::NIR::Call.new(
          node.id,
          node.name,
          node.args.map { |arg| rewrite_expr(arg) },
          node.targets,
          node.block.try { |block| rewrite_expr(block).as(IR::NIR::BlockLiteral) },
          node.type,
          node.span,
          node.primitive,
          node.name_span,
          node.method_site,
          node.dispatch_receiver
        )
      end
    end
  end
end
