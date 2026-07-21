module Tango
  module IR
    module LIR
      # Shared structural traversal for LIR consumers that need to see through
      # target-facing nodes without duplicating their child relationships.
      module Walk
        alias Node = Stmt | Value

        def self.children(stmt : Stmt) : Array(Node)
          case stmt
          when ChanSend
            nodes(stmt.channel, stmt.value)
          when ChanClose
            nodes(stmt.channel)
          when Spawn
            nodes(stmt.proc)
          when StringEachChar
            nodes(stmt.string, stmt.block)
          when Select
            children = Array(Node).new
            stmt.arms.each do |arm|
              children << arm.channel
              arm.value.try { |value| children << value }
              append(children, arm.body)
            end
            stmt.default.try { |body| append(children, body) }
            children
          when FieldAssign
            nodes(stmt.receiver, stmt.value)
          when ExternalCall
            nodes(stmt.args)
          when Assign, Discard
            nodes(stmt.value)
          when If
            children = nodes(stmt.cond)
            append(children, stmt.then_body)
            append(children, stmt.else_body)
            children
          when While
            children = nodes(stmt.cond)
            append(children, stmt.body)
            children
          when Handler
            children = nodes(stmt.body)
            stmt.clauses.each { |clause| append(children, clause.body) }
            stmt.else_body.try { |body| append(children, body) }
            stmt.ensure_body.try { |body| append(children, body) }
            children
          when AbruptExit
            children = Array(Node).new
            stmt.value.try { |value| children << value }
            children
          when UnsupportedStmt
            Array(Node).new
          else
            raise ArgumentError.new("unhandled LIR statement: #{stmt.class.name}")
          end
        end

        def self.children(value : Value) : Array(Node)
          case value
          when ExceptionValue
            children = Array(Node).new
            value.message.try { |child| children << child }
            children
          when Box
            children = Array(Node).new
            value.value.try { |child| children << child }
            children
          when MakeChan
            children = Array(Node).new
            value.capacity.try { |child| children << child }
            children
          when Unbox, NilCheck, Widen, Not, TypeTest, Cast, AddressOf,
               NumericConvert, IntegerConvert, FloatToIntegerConvert,
               FloatIntrinsic, IntegerNegate
            nodes(value.value)
          when IntegerBitNot
            nodes(value.operand)
          when ScalarStringify
            children = nodes(value.effects)
            value.value.try { |child| children << child }
            children
          when Interpolation
            nodes(value.pieces.map(&.as(Value)))
          when Binary, CheckedArithmetic, IntegerOperationValue, FloatArithmetic, FloorArithmetic, StringCompare
            nodes(value.left, value.right)
          when IfValue
            nodes(value.cond, value.then_value, value.else_value)
          when RescueValue
            children = Array(Node).new
            append(children, value.body)
            value.clauses.each { |clause| append(children, clause.body) }
            value.else_arm.try { |arm| append(children, arm) }
            value.ensure_body.try { |body| append(children, body) }
            children
          when Call, ExternalCallValue
            nodes(value.args)
          when FieldAccess
            nodes(value.receiver)
          when Closure
            nodes(value.body)
          when InvokeClosure
            children = nodes(value.callee)
            append(children, value.args)
            children
          when ArrayBuild
            nodes(value.size)
          when ArrayGet
            nodes(value.array, value.index)
          when ArraySet
            nodes(value.array, value.index, value.value)
          when ArrayPush
            nodes(value.array, value.value)
          when MaterializedStringSplit
            children = nodes(value.string)
            value.separator.try { |separator| children << separator }
            children
          when CollectionCount
            nodes(value.source.value)
          when FusedCollectionTraversal
            children = nodes(value.source.value)
            if source = value.source.as?(StringSegments)
              children << source.separator
            end
            value.transforms.each { |transform| children << transform.block }
            if terminal = value.terminal.as?(CollectionFoldTerminal)
              children << terminal.initial
            end
            children << value.terminal.block
            children
          when StringCharAt
            nodes(value.string, value.index)
          when StringToFloat
            nodes(value.string)
          when StringToInteger
            nodes(value.string) + nodes(value.options)
          when HashGet, HashHasKey
            nodes(value.hash, value.key)
          when HashKeyAt
            nodes(value.hash, value.index)
          when HashSet
            nodes(value.hash, value.key, value.value)
          when HashFetch
            nodes(value.hash, value.key, value.default)
          when ValueSequence
            children = nodes(value.body)
            children << value.value
            children
          when ChanReceive, ChanReceiveMaybe, ChanReceiveMaybeBox, ChanReceiveState
            nodes(value.channel)
          when IntConst, FloatConst, StringConst, EnumConst, GlobalRef, BoolConst, UnsupportedValue,
               NilConst, NilValue, Temp, Alloc, MakeMutex, ArrayNew, HashNew
            Array(Node).new
          else
            raise ArgumentError.new("unhandled LIR value: #{value.class.name}")
          end
        end

        private def self.append(children : Array(Node), values : Array(Stmt) | Array(Value)) : Array(Node)
          values.each { |value| children << value }
          children
        end

        private def self.append(children : Array(Node), arm : RescueValue::Arm) : Array(Node)
          append(children, arm.body)
          arm.value.try { |value| children << value }
          children
        end

        private def self.nodes(*values : Node) : Array(Node)
          children = Array(Node).new(values.size)
          values.each { |value| children << value }
          children
        end

        private def self.nodes(values : Array(Stmt) | Array(Value)) : Array(Node)
          children = Array(Node).new(values.size)
          append(children, values)
        end
      end
    end
  end
end
