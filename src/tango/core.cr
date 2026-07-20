# Standalone host-neutral compiler core. Bootstrap and semantic-bundle
# consumers load this entrypoint without loading the Crystal frontend or the
# product shell.
require "./node_id"
require "./source"
require "./ir"
require "./expansion"
require "./diagnostics"
require "./frontend/contract"
require "./analysis"
require "./planning"
require "./lowering"
require "./target"
require "./compiler/kernel"
