module BundleSpec
  extend self

  def result : Tango::Frontend::Result
    entrypoint = Tango::Source::File.new(
      "/workspace/main.tn",
      "require \"./answer\"\nputs answer\n",
      identity: "source-main",
      stable_path: false
    )
    dependency = Tango::Source::File.new(
      "/workspace/answer.tn",
      "def answer\n  42\nend\n",
      identity: "source-answer"
    )
    require_range = Tango::Source::Range.new(entrypoint.path, 0, 18, 1, 1)
    value_range = Tango::Source::Range.new(dependency.path, 13, 15, 2, 3)
    source = Tango::Source::CompilationUnit.new(
      [entrypoint, dependency],
      entrypoint,
      [Tango::Source::RequireDirective.new(entrypoint.path, "./answer", require_range)],
      [Tango::Source::RequireEdge.new(entrypoint.path, "./answer", dependency.path, require_range)]
    )
    int_type = Tango::IR::Type.int(:i32)
    literal = Tango::IR::NIR::IntLiteral.new(
      Tango::NodeId.new("semantic-42"),
      "42",
      int_type,
      value_range
    )
    type_annotation = Tango::IR::NIR::TargetAnnotation.new(
      ["Go", "Type"],
      ["int32"],
      ["value"]
    )
    program = Tango::IR::NIR::Program.new(
      [literal] of Tango::IR::NIR::Stmt,
      {int_type => [type_annotation]}
    )
    callable_range = Tango::Source::Range.new(dependency.path, 0, dependency.code.bytesize, 1, 1)
    declaration = Tango::Frontend::SyntaxSurface::Declaration.new(
      "answer",
      Tango::Frontend::SyntaxSurface::DeclarationKind::Function,
      callable_range,
      Tango::Source::Range.new(dependency.path, 4, 10, 1, 5),
      detail: "answer : Int32",
      documentation: "The answer.",
      callable_kind: Tango::Frontend::SyntaxSurface::CallableKind::Function,
      parameters: [Tango::Frontend::SyntaxSurface::Parameter.new("scale", "Int32", "Multiplier")],
      scope_id: "answer-scope"
    )
    scope = Tango::Frontend::SyntaxSurface::Scope.new(
      Tango::Frontend::SyntaxSurface::ScopeKind::Callable,
      callable_range,
      nil,
      "answer-scope"
    )
    fix = Tango::Diagnostic::Fix.new(
      Tango::Diagnostic::FixKind::PrefixUnusedLocal,
      "Prefix unused local",
      [Tango::Source::Edit.new(value_range, "_answer")]
    )
    diagnostic = Tango::Diagnostic.new(
      Tango::Diagnostic::Origin::Frontend,
      Tango::Diagnostic::Severity::Warning,
      "front.fixture",
      "fixture warning",
      file: dependency.path,
      line: 2,
      column: 3,
      size: 2,
      detail: "fixture detail",
      unnecessary: true,
      range: value_range,
      related: [{require_range, "loaded here"}],
      hints: ["fixture hint"],
      fix: fix
    )

    Tango::Frontend::Result.new(
      source,
      program,
      [diagnostic],
      Tango::Frontend::SyntaxSurface::Index.new([declaration], [scope])
    )
  end

  def document : Tango::Frontend::Bundle::Document
    Tango::Frontend::Bundle::Document.from(
      result,
      frontend_version: "fixture-frontend",
      prelude_version: "fixture-prelude"
    )
  end
end
