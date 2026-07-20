module Tango
  module Analysis
    module Passes
      class Blocks
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(program, table)
        end

        def run(program : IR::NIR::Program, table : Facts::Table) : Nil
          @spawning_defs = collect_spawning_defs(program)
          children = IR::NIR::Walk.children(program)
          outer = scope_locals(children)
          children.each { |stmt| visit(stmt, outer, table) }
        end

        @spawning_defs = Set(NodeId).new

        # A block escapes when it is handed to a def that forwards it to the
        # goroutine primitive: the goroutine may outlive the frame. A GC'd Go
        # backend needs no env-struct capture for this — the fact drives tooling
        # (which locals outlive the frame), not representation.
        # A block literal usually appears as a `Call#block`; semantic collection
        # transforms retain that Call as their fallback, and StringEachChar
        # owns one directly. Every path records the same captures and scope
        # facts; only a resolved call can escape via spawn.
        # `outer` is the set of locals bound in enclosing scopes, threaded so a
        # reassignment of an enclosing local reads as a capture, not a fresh
        # block-local.
        private def visit(node : IR::NIR::Stmt, outer : Set(String), table : Facts::Table) : Nil
          call = case node
                 when IR::NIR::Call                        then node
                 when IR::NIR::SemanticCollectionOperation then node.fallback
                 end
          if call && (block = call.block)
            call.args.each { |arg| visit(arg, outer, table) }
            resolved = table.internal_calls[node.id]?
            escapes = resolved ? @spawning_defs.includes?(resolved.definition) : false
            visit_block(block, outer, escapes, table)
          elsif node.is_a?(IR::NIR::StringEachChar)
            visit(node.string, outer, table)
            visit_block(node.block, outer, false, table)
          elsif node.is_a?(IR::NIR::Def)
            # A def opens a fresh scope — its body never captures enclosing locals.
            def_scope = Set(String).new
            node.params.each { |param| def_scope << param.name }
            node.block_param.try { |block_param| def_scope << block_param.name }
            def_scope.concat(scope_locals(IR::NIR::Walk.children(node)))
            IR::NIR::Walk.children(node).each { |child| visit(child, def_scope, table) }
          else
            IR::NIR::Walk.children(node).each { |child| visit(child, outer, table) }
          end
        end

        private def record_block(block : IR::NIR::BlockLiteral, outer : Set(String), escapes : Bool, table : Facts::Table) : Nil
          table.blocks[block.id] = Facts::BlockFacts.new(captured(block, outer, table), escapes)
        end

        private def visit_block(block : IR::NIR::BlockLiteral, outer : Set(String), escapes : Bool, table : Facts::Table) : Nil
          record_block(block, outer, escapes, table)
          inner = outer.dup
          block.args.each { |arg| inner << arg.name }
          inner.concat(scope_locals(IR::NIR::Walk.children(block)))
          IR::NIR::Walk.children(block).each { |child| visit(child, inner, table) }
        end

        # Locals declared directly in this scope — Assign targets, not descending
        # into nested defs or block literals, which open their own scopes.
        private def scope_locals(nodes : Array(IR::NIR::Stmt)) : Set(String)
          locals = Set(String).new
          nodes.each { |node| collect_scope_locals(node, locals) }
          locals
        end

        private def collect_scope_locals(node : IR::NIR::Stmt, locals : Set(String)) : Nil
          return if node.is_a?(IR::NIR::Def) || node.is_a?(IR::NIR::BlockLiteral)
          if node.is_a?(IR::NIR::Assign) && (target = node.target).is_a?(IR::NIR::Local)
            locals << target.name
          end
          IR::NIR::Walk.children(node).each { |child| collect_scope_locals(child, locals) }
        end

        # Defs whose `&block` parameter reaches a `Spawn` — i.e. `spawn` and any
        # wrapper that forwards its block to a goroutine.
        private def collect_spawning_defs(program : IR::NIR::Program) : Set(NodeId)
          definitions = Set(NodeId).new
          program.body.each do |stmt|
            next unless stmt.is_a?(IR::NIR::Def)
            block_param = stmt.block_param
            next unless block_param
            definitions << stmt.id if forwards_to_spawn?(stmt.body, block_param.name)
          end
          definitions
        end

        private def forwards_to_spawn?(node : IR::NIR::Stmt, block_name : String) : Bool
          if node.is_a?(IR::NIR::Spawn)
            proc = node.proc
            return true if proc.is_a?(IR::NIR::Local) && proc.name == block_name
          end
          IR::NIR::Walk.children(node).any? { |child| forwards_to_spawn?(child, block_name) }
        end

        # Free variables of a block: names referenced inside it — read or
        # reassigned — that are bound in an enclosing scope (`outer`). Block args
        # and names first declared inside the block are its own locals, not
        # captures; an assignment to an `outer` name is a captured write.
        private def captured(block : IR::NIR::BlockLiteral, outer : Set(String), table : Facts::Table) : Array(Facts::Capture)
          block_local = Set(String).new
          block.args.each { |arg| block_local << arg.name }
          collect_block_locals(block.body, outer, block_local)

          names = [] of String
          collect_captured(block.body, outer, block_local, names)
          names.compact_map do |name|
            capture_declaration(block.body, name, table).try do |declaration|
              Facts::Capture.new(declaration, name)
            end
          end
        end

        private def collect_block_locals(node : IR::NIR::Stmt, outer : Set(String), block_local : Set(String)) : Nil
          return if node.is_a?(IR::NIR::BlockLiteral)
          if node.is_a?(IR::NIR::Assign) && (target = node.target).is_a?(IR::NIR::Local)
            block_local << target.name unless outer.includes?(target.name)
          end
          IR::NIR::Walk.children(node).each { |child| collect_block_locals(child, outer, block_local) }
        end

        private def collect_captured(node : IR::NIR::Stmt, outer : Set(String), block_local : Set(String), captured : Array(String)) : Nil
          # Nested defs/blocks own their own free-variable set. Descending here
          # made an outer block claim captures referenced only by an inner one.
          return if node.is_a?(IR::NIR::Def) || node.is_a?(IR::NIR::BlockLiteral)
          case node
          when IR::NIR::Local
            add_capture(node.name, outer, block_local, captured)
          when IR::NIR::Assign
            target = node.target
            if target.is_a?(IR::NIR::Local)
              add_capture(target.name, outer, block_local, captured)
            else
              collect_captured(target, outer, block_local, captured)
            end
            collect_captured(node.value, outer, block_local, captured)
            return
          end
          IR::NIR::Walk.children(node).each { |child| collect_captured(child, outer, block_local, captured) }
        end

        private def add_capture(name : String, outer : Set(String), block_local : Set(String), captured : Array(String)) : Nil
          return if block_local.includes?(name)
          return unless outer.includes?(name)
          captured << name unless captured.includes?(name)
        end

        private def capture_declaration(node : IR::NIR::Stmt, name : String, table : Facts::Table) : NodeId?
          return nil if node.is_a?(IR::NIR::Def) || node.is_a?(IR::NIR::BlockLiteral)
          if node.is_a?(IR::NIR::Local) && node.name == name
            reference = table.references[node.id]?
            return reference.declaration if reference.is_a?(Facts::LocalReference)
          end
          IR::NIR::Walk.children(node).each do |child|
            capture_declaration(child, name, table).try { |declaration| return declaration }
          end
          nil
        end
      end
    end
  end
end
