require "./editor/index"
require "./editor/hierarchy_builder"
require "./editor/context"
require "./editor/callables"
require "./editor/completion"
require "./editor/definition"
require "./editor/hover"
require "./editor/hover_text"
require "./editor/inlay_hints"
require "./editor/rename"
require "./editor/semantic_tokens"
require "./editor/type_definition"
require "./editor/type_hierarchy"

module Tango
  module Compiler
    # Protocol-neutral editor query subsystem. Consumers require this barrel;
    # individual query implementations remain internal organization details.
    module Editor
    end
  end
end
