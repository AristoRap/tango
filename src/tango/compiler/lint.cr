module Tango
  module Compiler
    # Advisory diagnostics consume analysis facts rather than re-walking NIR:
    # one local-use proof therefore drives both the Go-safe lowering and every
    # user-facing consumer (CLI, snapshot clients, and the LSP).
    module Lint
      def self.run(facts : Analysis::Facts::Table, index : Editor::Index) : Array(Diagnostic)
        index.declarations.compact_map do |declaration|
          next unless declaration.kind.local?
          next unless facts.unused_locals.includes?(declaration.id.declaration)

          range = declaration.range
          fix = Diagnostic::Fix.new(
            Diagnostic::FixKind::PrefixUnusedLocal,
            "Prefix '#{declaration.name}' with '_'",
            [Diagnostic::FixEdit.new(range, "_#{declaration.name}")]
          )
          Diagnostic.new(
            Diagnostic::Origin::Lint,
            Diagnostic::Severity::Warning,
            Diagnostics::LINT_UNUSED_LOCAL,
            "unused local variable '#{declaration.name}' — assigned but never read",
            file: range.path,
            line: range.line || 1,
            column: range.column || 1,
            size: {range.length, 1}.max,
            unnecessary: true,
            range: range,
            fix: fix
          )
        end
      end
    end
  end
end
