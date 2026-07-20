require "compiler/crystal/annotatable"
require "compiler/crystal/program"
require "compiler/crystal/config"
require "compiler/crystal/crystal_path"
require "compiler/crystal/error"
require "compiler/crystal/exception"
require "compiler/crystal/progress_tracker"
require "compiler/crystal/syntax"
require "compiler/crystal/formatter"
require "compiler/crystal/types"
require "compiler/crystal/util"
require "compiler/crystal/warnings"
require "compiler/crystal/tools/dependencies"
require "compiler/crystal/compiler"
require "compiler/crystal/semantic"
require "compiler/crystal/macros/*"
require "compiler/crystal/codegen/*"

module Tango
  module Frontend
    module Crystal
      module Semantic
        PRELUDE = ::Tango::Workspace::Layout.prelude_require

        def self.parse(source : String, filename : String) : ::Crystal::ASTNode
          parser = ::Crystal::Parser.new(source)
          parser.filename = filename
          parser.parse
        end

        def self.compile(source : String, filename : String) : ::Crystal::Compiler::Result
          compile(Source::CompilationUnit.single(Source::File.new(filename, source)))
        end

        def self.compile(unit : Source::CompilationUnit) : ::Crystal::Compiler::Result
          ::Tango::Toolchain::Crystal.setup!

          compiler = ::Crystal::Compiler.new
          compiler.no_codegen = true
          compiler.prelude = PRELUDE
          sources = unit.files.map do |file|
            ::Crystal::Compiler::Source.new(file.path, unit.semantic_code(file))
          end
          compiler.compile(sources, "/dev/null")
        end
      end
    end
  end
end
