require "file_utils"

module Tango
  module CLI
    module Clean
      record Result, path : String, removed : Bool, diagnostic : Diagnostic? = nil

      def self.run : Result
        path = File.expand_path(Workspace::Layout::MODULE_ROOT)
        begin
          return Result.new(path, false) unless File.exists?(path)

          FileUtils.rm_rf(path)
          Result.new(path, true)
        rescue ex
          diagnostic = Diagnostic.new(
            Diagnostic::Origin::Check,
            Diagnostic::Severity::Error,
            Diagnostics::CHECK_CLEAN,
            "could not clean #{path}: #{ex.message}",
            detail: ex.to_s
          )
          Result.new(path, false, diagnostic)
        end
      end
    end
  end
end
