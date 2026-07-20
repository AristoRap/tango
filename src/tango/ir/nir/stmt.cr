module Tango
  module IR
    module NIR
      # Root NIR node: anything with identity and a span. `Stmt` means
      # "NIR node," not necessarily "executable statement" — binding nodes
      # like Param and BlockArg are Stmts so they participate in dumps,
      # span indexing, and traversal without a second root type.
      abstract class Stmt
        getter id : NodeId
        getter span : Source::Range?

        def initialize(@id : NodeId, @span : Source::Range?)
        end
      end

      class Block < Stmt
        getter body : Array(Stmt)

        def initialize(id : NodeId, @body : Array(Stmt), span : Source::Range?)
          super(id, span)
        end
      end
    end
  end
end
