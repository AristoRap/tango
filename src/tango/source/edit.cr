module Tango
  module Source
    # One protocol-neutral replacement over an exact source range. Rename and
    # diagnostic fixes share this shape before an LSP client chooses how to
    # apply it.
    record Edit, range : Range, new_text : String
  end
end
