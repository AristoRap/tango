module Tango
  module Workspace
    module Layout
      MODULE_ROOT = ".tango"
      SOURCE_EXTS = {".tn", ".cr"}
      SOURCE_ROOT = File.expand_path("../../..", __DIR__)

      def self.stem(path : String) : String
        strip_source_ext(File.basename(path))
      end

      def self.module_dir(path : String) : String
        File.join(MODULE_ROOT, stem(path))
      end

      def self.module_file(path : String) : String
        File.join(module_dir(path), "main.go")
      end

      def self.cache_dir : String
        File.join(MODULE_ROOT, "cache")
      end

      def self.go_build_cache_dir : String
        File.expand_path(File.join(cache_dir, "go-build"))
      end

      def self.go_module_cache_dir : String
        File.expand_path(File.join(cache_dir, "go-mod"))
      end

      def self.go_temp_dir : String
        File.expand_path(File.join(cache_dir, "go-tmp"))
      end

      def self.build_output(path : String) : String
        "./#{stem(path)}"
      end

      def self.slug(path : String, root : String = repo_root) : String
        strip_source_ext(path.sub("#{root}/", "").gsub('/', '_'))
      end

      def self.repo_root : String
        resolve_repo_root(ENV["TANGO_HOME"]?, Process.executable_path)
      end

      def self.resolve_repo_root(explicit : String?, executable : String?, source_root : String = SOURCE_ROOT) : String
        return File.expand_path(explicit) if explicit && !explicit.empty?

        if executable
          executable_dir = File.dirname(File.expand_path(executable))
          [executable_dir, File.dirname(executable_dir)].each do |candidate|
            return candidate if File.file?(File.join(candidate, "prelude", "tango.cr"))
          end
        end

        source_root
      end

      def self.prelude_dir : String
        File.join(repo_root, "prelude")
      end

      def self.prelude_file : String
        File.join(prelude_dir, "tango.cr")
      end

      def self.prelude_require : String
        "tango"
      end

      def self.bundled_packages_dir : String
        File.join(repo_root, "stdlib")
      end

      def self.bundled_package_path?(path : String) : Bool
        root = File.expand_path(bundled_packages_dir)
        expanded = File.expand_path(path)
        expanded.starts_with?("#{root}#{File::SEPARATOR}")
      end

      def self.tango_bin : String
        File.join(repo_root, "bin", "tango")
      end

      private def self.strip_source_ext(name : String) : String
        SOURCE_EXTS.each { |ext| return name.rchop(ext) if name.ends_with?(ext) }
        name
      end
    end
  end
end
