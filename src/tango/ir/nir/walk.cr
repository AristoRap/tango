module Tango
  module IR
    module NIR
      # Shared traversal seam so dumps, span indexing, and analysis do not
      # duplicate child-recursion rules.
      module Walk
        def self.children(program : Program) : Array(Stmt)
          program.body
        end

        # Every structural child, including binding/write positions:
        # Assign#target, Def#params, and BlockLiteral#args.
        def self.children(node : Stmt) : Array(Stmt)
          case node
          when Block
            node.body
          when Assign
            [node.target, node.value] of Stmt
          when If
            kids = [node.cond, node.then_branch] of Stmt
            node.else_branch.try { |else_branch| kids << else_branch }
            kids
          when While
            [node.cond, node.body] of Stmt
          when Return, Break, Next
            kids = Array(Stmt).new
            node.value.try { |value| kids << value }
            kids
          when Raise
            [node.value] of Stmt
          when ExceptionNew
            kids = Array(Stmt).new
            node.message.try { |message| kids << message }
            kids
          when ExceptionHandler
            kids = [node.body] of Stmt
            node.clauses.each do |clause|
              clause.binding.try { |binding| kids << binding }
              kids << clause.body
            end
            node.else_branch.try { |branch| kids << branch }
            node.ensure_branch.try { |branch| kids << branch }
            kids
          when Def
            kids = Array(Stmt).new
            node.params.each { |param| kids << param }
            node.block_param.try { |block_param| kids << block_param }
            node.return_type_reference.try { |reference| kids << reference }
            kids << node.body
          when Class
            node.initializers.map(&.as(Stmt))
          when Enum
            Array(Stmt).new
          when Namespace
            [node.body] of Stmt
          when Constant
            [node.value] of Stmt
          when TypeAlias, TypeAliasReference
            Array(Stmt).new
          when FieldInitializer
            [node.value] of Stmt
          when BlockLiteral
            kids = Array(Stmt).new
            node.args.each { |arg| kids << arg }
            kids << node.body
          when InvokeBlock
            kids = [node.receiver] of Stmt
            node.args.each { |arg| kids << arg }
            kids
          when Call
            kids = Array(Stmt).new
            node.dispatch_receiver.try { |receiver| kids << receiver }
            node.args.each { |arg| kids << arg }
            node.block.try { |block| kids << block }
            kids
          when SemanticOperation
            kids = node.fallback.args.map(&.as(Stmt))
            node.fallback.block.try { |block| kids << block }
            kids
          when Interpolation
            node.pieces.map(&.as(Stmt))
          when StringSplit
            kids = [node.string] of Stmt
            node.separator.try { |separator| kids << separator }
            kids
          when Size
            [node.value] of Stmt
          when StringCharAt
            [node.string, node.index] of Stmt
          when StringEachChar
            [node.string, node.block] of Stmt
          when StringToFloat
            [node.string] of Stmt
          when StringToInteger
            [node.string.as(Stmt)] + node.options.map(&.as(Stmt))
          when Not
            [node.value] of Stmt
          when TypeTest, Cast
            [node.value] of Stmt
          when HashGet
            [node.hash, node.key] of Stmt
          when HashSet
            [node.hash, node.key, node.value] of Stmt
          when HashFetch
            [node.hash, node.key, node.default] of Stmt
          when HashHasKey
            [node.hash, node.key] of Stmt
          when HashKeyAt
            [node.hash, node.index] of Stmt
          when ArrayBuild
            [node.size] of Stmt
          when ArrayGet
            [node.array, node.index] of Stmt
          when ArraySet
            [node.array, node.index, node.value] of Stmt
          when ArrayPush
            [node.array, node.value] of Stmt
          when ValueSequence
            [node.prefix, node.value] of Stmt
          when New
            kids = Array(Stmt).new
            node.args.each { |arg| kids << arg }
            kids
          when Spawn
            [node.proc] of Stmt
          when ChannelNew
            kids = Array(Stmt).new
            node.capacity.try { |capacity| kids << capacity }
            kids
          when ChannelOp
            kids = [node.channel] of Stmt
            node.value.try { |value| kids << value }
            kids
          when Select
            kids = Array(Stmt).new
            node.arms.each do |arm|
              arm.captured.try { |captured| kids << captured }
              kids << arm.channel
              arm.value.try { |value| kids << value }
              kids << arm.body
            end
            node.else_body.try { |else_body| kids << else_body }
            kids
          when ArrayNew, HashNew, MutexNew, IntLiteral, FloatLiteral,
               StringLiteral, BoolLiteral, NilLiteral, Local, ClassRef, InstanceVar,
               EnumMember, ConstantReference, Param, BlockArg, BlockParam, UnsupportedExpr
            Array(Stmt).new
          else
            raise ArgumentError.new("unhandled NIR node: #{node.class.name}")
          end
        end

        # Structural children minus pure binding/write positions. Use only
        # for passes where declaration/write locations are irrelevant.
        def self.non_binding_children(node : Stmt) : Array(Stmt)
          case node
          when Assign
            [node.value] of Stmt
          when Def
            [node.body] of Stmt
          when BlockLiteral
            [node.body] of Stmt
          when Select
            kids = Array(Stmt).new
            node.arms.each do |arm|
              kids << arm.channel
              arm.value.try { |value| kids << value }
              kids << arm.body
            end
            node.else_body.try { |else_body| kids << else_body }
            kids
          when ExceptionHandler
            kids = [node.body] of Stmt
            node.clauses.each { |clause| kids << clause.body }
            node.else_branch.try { |branch| kids << branch }
            node.ensure_branch.try { |branch| kids << branch }
            kids
          else
            children(node)
          end
        end
      end
    end
  end
end
