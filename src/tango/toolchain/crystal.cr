module Tango
  module Toolchain
    module Crystal
      enum Source
        Explicit
        CrystalEnv
      end

      record Path, base : String, source : Source

      class SetupError < Exception
      end

      def self.choose(explicit : String?, discovered : String?) : Path | String
        return Path.new(explicit, Source::Explicit) if explicit && !explicit.empty?
        return Path.new(discovered, Source::CrystalEnv) if discovered && !discovered.empty?

        "cannot locate Crystal's src directory: set CRYSTAL_PATH or put `crystal` on PATH"
      end

      def self.resolve : Path | String
        explicit = ENV["CRYSTAL_PATH"]?
        discovered = explicit ? nil : discover
        choose(explicit, discovered)
      end

      @@ready = false

      def self.setup! : Nil
        return nil if @@ready

        setup!(resolve)
      end

      # The explicit-result overload keeps resolution testable without making
      # callers reimplement setup's failure contract.
      def self.setup!(result : Path | String) : Nil
        case result
        in Path
          return nil if @@ready

          prelude_dir = Workspace::Layout.prelude_dir
          base = result.base
          entries = base.split(Process::PATH_DELIMITER, remove_empty: true)
          ENV["CRYSTAL_PATH"] = entries.includes?(prelude_dir) ? base : ([prelude_dir] + entries).join(Process::PATH_DELIMITER)
          @@ready = true
          nil
        in String
          raise SetupError.new(result)
        end
      end

      private def self.discover : String?
        output = IO::Memory.new
        status = Process.run("crystal", ["env", "CRYSTAL_PATH"], output: output, error: Process::Redirect::Close)
        return nil unless status.success?

        output.to_s.strip.presence
      rescue
        nil
      end
    end
  end
end
