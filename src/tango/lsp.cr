require "./lsp/json_rpc"
require "./lsp/position"
require "./lsp/analysis_codec"
require "./lsp/analysis_worker"
require "./lsp/document"
require "./lsp/root_ownership_index"
require "./lsp/workspace"
require "./lsp/recovery_query"
require "./lsp/uri_path"
require "./lsp/type_hierarchy"
require "./lsp/server"
require "./lsp/server_diagnostics"

if Tango::Lsp::AnalysisWorker.child_process?
  Tango::Lsp::AnalysisWorker.run_child
  Process.exit(0)
end
