require "spec"
require "../src/tango"

def expect_present(value : T?, message = "expected value to be present", file = __FILE__, line = __LINE__) : T forall T
  value || fail(message, file, line)
end
