module Tango
  module Diagnostics
    FRONT_SYNTAX            = "front.syntax"
    FRONT_TYPE              = "front.type"
    FRONT_REQUIRE           = "front.require"
    FRONT_REQUIRE_TOP_LEVEL = "front.require-top-level"
    EMIT_UNSUPPORTED        = "emit.unsupported"
    INTERNAL_RESERVED       = "internal.reserved"
    CHECK_GOFMT             = "check.gofmt"
    CHECK_GO_VET            = "check.go-vet"
    CHECK_CRYSTAL           = "check.crystal"
    CHECK_CRYSTAL_PATH      = "check.crystal-path"
    CHECK_PRELUDE           = "check.prelude"
    CHECK_GO                = "check.go"
    CHECK_GO_VERSION        = "check.go-version"
    CHECK_CLEAN             = "check.clean"
    CHECK_FORMATTER         = "check.formatter"
    LINT_RETURN_TYPE        = "lint.return-type"
    LINT_UNUSED_LOCAL       = "lint.unused-local"
    LINT_UNUSED_BLOCK_ARG   = "lint.unused-block-arg"
    LINT_RAW_MACRO          = "lint.raw-macro"

    EMIT_PREFIX = "emit error: "
    CLI_PREFIX  = "tango: "
  end
end
