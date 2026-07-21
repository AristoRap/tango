require "spec"

module GuardrailsSpec
  MAX_LINES = 800
  ROOT      = File.expand_path("..", __DIR__)

  PROJECT_GLOBS = {
    "src/**/*.cr",
    "spec/**/*.cr",
    "prelude/**/*.cr",
  }

  PUBLISHABLE_GLOBS = {
    "src/**/*.{cr,md}",
    "spec/**/*.{cr,tn,md}",
    "prelude/**/*.{cr,md}",
    "stdlib/**/*.{tn,md}",
    "examples/**/*.{tn,md}",
    "editors/**/*.{ts,json,md,yml,yaml}",
    "scripts/**/*.{cr,py,sh,md}",
    "README.md",
    "Makefile",
    "shard.yml",
  }

  INTERNAL_SHORTHAND = /\b(?:A\d{1,3}|D\d{1,3}|E\d{1,3}[A-Z]?|I0\d|M\d{1,3}[A-Z0-9-]*|R\d{1,3}|Milestone \d+)\b/i

  def self.project_files : Array(String)
    files = [] of String

    PROJECT_GLOBS.each do |glob|
      Dir.glob(File.join(ROOT, glob)).each do |path|
        files << path if File.file?(path)
      end
    end

    files.sort
  end

  def self.line_count(path : String) : Int32
    lines = 0
    File.each_line(path) { lines += 1 }
    lines
  end

  def self.forced_nil_assertions : Array(String)
    needle = "." + "not_nil!"
    project_files.flat_map do |path|
      relative_path = path.lchop("#{ROOT}/")
      matches = [] of String
      File.read(path).lines.each_with_index do |line, index|
        matches << "#{relative_path}:#{index + 1}" if line.includes?(needle)
      end
      matches
    end
  end

  def self.prelude_manifest_declarations : Array(String)
    path = File.join(ROOT, "prelude", "tango.cr")
    File.read(path).lines(chomp: true).reject do |line|
      stripped = line.strip
      stripped.empty? || stripped.starts_with?('#') || stripped.starts_with?(%(require "./tango/))
    end
  end

  def self.publishable_files : Array(String)
    PUBLISHABLE_GLOBS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
      .select { |path| File.file?(path) && !path.includes?("/node_modules/") }
      .uniq
      .sort
  end

  def self.internal_shorthand_leaks : Array(String)
    publishable_files.flat_map do |path|
      relative_path = path.lchop("#{ROOT}/")
      leaks = [] of String
      if relative_path.upcase.matches?(INTERNAL_SHORTHAND)
        leaks << "#{relative_path}: filename"
      end
      File.read(path).lines.each_with_index do |line, index|
        leaks << "#{relative_path}:#{index + 1}" if line.matches?(INTERNAL_SHORTHAND)
      end
      leaks
    end
  end
end

describe "source guardrails" do
  it "keeps project-owned files under the line budget" do
    oversized = GuardrailsSpec.project_files.compact_map do |path|
      lines = GuardrailsSpec.line_count(path)
      next unless lines > GuardrailsSpec::MAX_LINES

      relative_path = path.lchop("#{GuardrailsSpec::ROOT}/")
      "#{relative_path}: #{lines} lines"
    end

    oversized.should be_empty, <<-MESSAGE
    Crystal files over #{GuardrailsSpec::MAX_LINES} lines need to be split by responsibility:
    #{oversized.join('\n')}
    MESSAGE
  end

  it "keeps forced nil assertions out of project-owned Crystal" do
    offenders = GuardrailsSpec.forced_nil_assertions

    offenders.should be_empty, <<-MESSAGE
    Forced nil assertions bypass explicit control-flow narrowing and produce
    runtime failures with poor context. Narrow the optional value, return a
    structured error, or use expect_present in specs:
    #{offenders.join('\n')}
    MESSAGE
  end

  it "keeps the prelude entrypoint as an ordered manifest" do
    declarations = GuardrailsSpec.prelude_manifest_declarations

    declarations.should be_empty, <<-MESSAGE
    prelude/tango.cr is the ordered manifest for the implicit language surface.
    Put declarations in a responsibility-shaped file under prelude/tango/ and
    require that file from the manifest:
    #{declarations.join('\n')}
    MESSAGE
  end

  it "keeps internal planning shorthand out of publishable files" do
    offenders = GuardrailsSpec.internal_shorthand_leaks

    offenders.should be_empty, <<-MESSAGE
    Publishable source, specs, fixtures, and filenames must describe behavior
    directly instead of referring to private planning identifiers:
    #{offenders.join('\n')}
    MESSAGE
  end
end

# Phase-boundary purity: the funnel `frontend -> expansion -> ir ->
# analysis/planning -> lowering -> target` only holds if nothing upstream
# reaches for a downstream vocabulary.
module PhaseBoundarySpec
  ROOT = File.expand_path("..", __DIR__)

  # A `package.Func` selector — a lowercase package qualifier followed by an
  # exported identifier — is how a concrete Go API is spelled. It never occurs
  # in idiomatic Crystal (methods are snake_case, types are `Foo::Bar`), so
  # its presence upstream of target/go means a backend detail leaked into a
  # phase that must stay target-blind. The `@[Go(...)]` binding string lives in
  # the prelude and the golden fixtures, never in these source dirs.
  GO_SELECTOR = /\b[a-z][a-z0-9_]*\.[A-Z][A-Za-z0-9]*/

  # Phases upstream of target/go; none may name a Go API.
  TARGET_BLIND_DIRS = %w(
    src/tango/frontend
    src/tango/expansion
    src/tango/ir
    src/tango/analysis
    src/tango/planning
    src/tango/lowering
  )

  # Files reachable by the core driver's owned data contract and phase calls.
  # Product-shell composition and frontend adapters are deliberately excluded.
  CORE_HOST_NEUTRAL_PATHS = %w(
    src/tango/core.cr
    src/tango/node_id.cr
    src/tango/source.cr
    src/tango/source
    src/tango/frontend/result.cr
    src/tango/frontend/syntax_surface.cr
    src/tango/ir.cr
    src/tango/ir
    src/tango/expansion.cr
    src/tango/expansion
    src/tango/diagnostics.cr
    src/tango/diagnostics
    src/tango/analysis.cr
    src/tango/analysis
    src/tango/compiler/compilation_profile.cr
    src/tango/compiler/editor.cr
    src/tango/compiler/editor
    src/tango/compiler/lint.cr
    src/tango/compiler/snapshot.cr
    src/tango/compiler/core_driver.cr
    src/tango/planning.cr
    src/tango/planning
    src/tango/lowering.cr
    src/tango/lowering
    src/tango/target.cr
    src/tango/target
  )

  CRYSTAL_HOST_OWNERS = %w(
    src/tango/frontend/crystal
    src/tango/frontend/source_graph.cr
    src/tango/compiler/driver.cr
    src/tango/cli/doctor.cr
    src/tango/cli/format.cr
    src/tango/lsp/server.cr
  )

  def self.files_in(dir : String) : Array(String)
    Dir.glob(File.join(ROOT, dir, "**", "*.cr")).sort
  end

  def self.files_at(path : String) : Array(String)
    absolute = File.join(ROOT, path)
    File.file?(absolute) ? [absolute] : files_in(path)
  end

  def self.host_leaks : Hash(String, Array(String))
    problems = {} of String => Array(String)

    CORE_HOST_NEUTRAL_PATHS.flat_map { |path| files_at(path) }.uniq.sort.each do |path|
      text = File.read(path)
      hits = ["Crystal::"].select { |token| text.includes?(token) }
      problems[path.lchop("#{ROOT}/")] = hits unless hits.empty?
    end

    problems
  end

  def self.unclassified_host_leaks : Array(String)
    files_in("src/tango").compact_map do |path|
      next unless File.read(path).includes?("Crystal::")

      relative_path = path.lchop("#{ROOT}/")
      next if CRYSTAL_HOST_OWNERS.any? do |owner|
                relative_path == owner || relative_path.starts_with?("#{owner}/")
              end
      relative_path
    end
  end

  def self.leaks(dir : String, tokens : Array(String)) : Hash(String, Array(String))
    problems = {} of String => Array(String)

    files_in(dir).each do |path|
      text = File.read(path)
      hits = tokens.select { |token| text.includes?(token) }
      next if hits.empty?

      problems[path.lchop("#{ROOT}/")] = hits
    end

    problems
  end

  def self.selector_leaks : Hash(String, Array(String))
    problems = {} of String => Array(String)

    TARGET_BLIND_DIRS.each do |dir|
      files_in(dir).each do |path|
        hits = File.read(path).scan(GO_SELECTOR).map(&.[0]).uniq
        problems[path.lchop("#{ROOT}/")] = hits unless hits.empty?
      end
    end

    problems
  end

  def self.format(problems : Hash(String, Array(String))) : String
    problems.map { |file, hits| "#{file} mentions #{hits.inspect}" }.join('\n')
  end
end

describe "phase boundary guardrails" do
  it "keeps the self-hosting core slice Crystal-free" do
    problems = PhaseBoundarySpec.host_leaks

    problems.should be_empty, <<-MESSAGE
    The neutral frontend result and every dependency used by CoreDriver form
    the self-hosting core slice. Crystal compiler objects and adapters must
    remain behind frontend/crystal/ or in the product shell:
    #{PhaseBoundarySpec.format(problems)}
    MESSAGE
  end

  it "keeps every Crystal host dependency in an explicit owner" do
    problems = PhaseBoundarySpec.unclassified_host_leaks

    problems.should be_empty, <<-MESSAGE
    Crystal host dependencies belong in frontend/crystal or one of the named
    source-discovery and product-shell adapters. Move the dependency behind an
    owned boundary or classify a new adapter deliberately:
    #{problems.join('\n')}
    MESSAGE
  end

  it "keeps semantic expansion scheduled by the core driver" do
    schedulers = PhaseBoundarySpec.files_in("src/tango").select do |path|
      File.read(path).includes?("Expansion::Driver.run")
    end.map { |path| path.lchop("#{PhaseBoundarySpec::ROOT}/") }

    schedulers.should eq(["src/tango/compiler/core_driver.cr"]), <<-MESSAGE
    The frontend may retain resolved semantic annotations, but only CoreDriver
    may schedule the target-neutral expansion policy after the handoff:
    #{schedulers.join('\n')}
    MESSAGE
  end

  it "keeps the product pipeline behind the neutral frontend result seam" do
    pipeline = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango/compiler/pipeline.cr"))
    adapter_callers = PhaseBoundarySpec.files_in("src/tango").select do |path|
      File.read(path).includes?("Frontend::Crystal::Driver")
    end.map { |path| path.lchop("#{PhaseBoundarySpec::ROOT}/") }

    pipeline.should_not contain("Frontend::Crystal")
    pipeline.should_not contain("SyntaxSurfaceBuilder")
    pipeline.should_not contain("SourceGraph::Loader")
    adapter_callers.should eq(["src/tango/compiler/driver.cr"]), <<-MESSAGE
    Product requests must enter the retained Crystal adapter only through the
    in-process composition driver. Pipeline, graph failures, and editor-only
    snapshots cross the same Frontend::Result seam:
    #{adapter_callers.join('\n')}
    MESSAGE
  end

  it "routes composition entrypoints through owned manifests" do
    library = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango.cr"))
    core = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango/core.cr"))
    frontend = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango/frontend.cr"))
    frontend_contract = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango/frontend/contract.cr"))
    compiler = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango/compiler.cr"))
    compiler_kernel = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango/compiler/kernel.cr"))
    cli = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango/cli.cr"))
    semantic_transport = File.read(File.join(PhaseBoundarySpec::ROOT, "src/tango/cli/semantic_transport.cr"))
    executable = File.read(File.join(PhaseBoundarySpec::ROOT, "src/cli.cr"))

    library.lines.select(&.starts_with?("require ")).should eq([
      %(require "./tango/version"),
      %(require "./tango/compiler"),
    ])
    core.lines.select(&.starts_with?("require ")).should eq([
      %(require "./node_id"),
      %(require "./source"),
      %(require "./ir"),
      %(require "./expansion"),
      %(require "./diagnostics"),
      %(require "./frontend/contract"),
      %(require "./analysis"),
      %(require "./planning"),
      %(require "./lowering"),
      %(require "./target"),
      %(require "./compiler/kernel"),
    ])
    frontend.lines.select(&.starts_with?("require ")).should eq([
      %(require "./frontend/contract"),
      %(require "./frontend/crystal"),
    ])
    frontend_contract.lines.select(&.starts_with?("require ")).should eq([
      %(require "./syntax_surface"),
      %(require "./result"),
      %(require "./bundle"),
    ])
    compiler_kernel.lines.select(&.starts_with?("require ")).should eq([
      %(require "./compilation_profile"),
      %(require "./editor"),
      %(require "./lint"),
      %(require "./snapshot"),
      %(require "./core_driver"),
    ])
    compiler.lines.select(&.starts_with?("require ")).should contain(%(require "./frontend"))
    compiler.should_not contain(%(require "./frontend/crystal"))
    cli.lines.select(&.starts_with?("require ")).should eq([
      %(require "./version"),
      %(require "./compiler"),
      %(require "./dump"),
      %(require "./lsp"),
      %(require "./cli/source_input"),
      %(require "./cli/diagnostic_output"),
      %(require "./cli/semantic_transport"),
      %(require "./cli/clean"),
      %(require "./cli/doctor"),
      %(require "./cli/format"),
      %(require "./cli/command"),
    ])
    semantic_transport.lines.select(&.starts_with?("require ")).should eq([
      %(require "./semantic_transport/producer"),
      %(require "./semantic_transport/consumer"),
    ])
    executable.lines.select(&.starts_with?("require ")).should eq([%(require "./tango/cli")])
  end

  it "frontend/ stays backend-blind: no Go/target vocabulary" do
    problems = PhaseBoundarySpec.leaks("src/tango/frontend", ["Target::", "Go::", "package main", "gofmt"])
    problems.should be_empty, <<-MESSAGE
    frontend/ must never mention Go — it normalizes Crystal, nothing else:
    #{PhaseBoundarySpec.format(problems)}
    MESSAGE
  end

  it "ir/ carries neither Crystal compiler nodes nor Go vocabulary" do
    problems = PhaseBoundarySpec.leaks("src/tango/ir", ["Crystal::", "Target::", "Go::"])
    problems.should be_empty, <<-MESSAGE
    ir/ is tango's own language model — no Crystal compiler nodes, no Go:
    #{PhaseBoundarySpec.format(problems)}
    MESSAGE
  end

  it "analysis/ and planning/ carry neither Crystal compiler nodes nor Go vocabulary" do
    problems = PhaseBoundarySpec.leaks("src/tango/analysis", ["Crystal::", "Target::", "Go::"])
    problems.merge!(PhaseBoundarySpec.leaks("src/tango/planning", ["Crystal::", "Target::", "Go::"]))
    problems.should be_empty, <<-MESSAGE
    analysis/ may add facts and planning/ may pick strategies, but neither may
    reach for Crystal compiler nodes or Go vocabulary:
    #{PhaseBoundarySpec.format(problems)}
    MESSAGE
  end

  it "lowering/ carries neither Crystal compiler nodes nor Go vocabulary" do
    problems = PhaseBoundarySpec.leaks("src/tango/lowering", ["Crystal::", "Target::", "Go::"])
    problems.should be_empty, <<-MESSAGE
    lowering/ commits to LIR shapes using facts and plans only, never Crystal
    compiler nodes or Go vocabulary directly:
    #{PhaseBoundarySpec.format(problems)}
    MESSAGE
  end

  it "upstream phases do not depend on LIR" do
    problems = PhaseBoundarySpec.leaks("src/tango/frontend", ["IR::LIR"])
    problems.merge!(PhaseBoundarySpec.leaks("src/tango/expansion", ["IR::LIR"]))
    problems.merge!(PhaseBoundarySpec.leaks("src/tango/analysis", ["IR::LIR"]))
    problems.merge!(PhaseBoundarySpec.leaks("src/tango/planning", ["IR::LIR"]))
    problems.merge!(PhaseBoundarySpec.leaks("src/tango/ir/nir", ["LIR::"]))
    problems.should be_empty, <<-MESSAGE
    Frontend, expansion, NIR, analysis, and planning must not construct or
    depend on LIR;
    lowering owns the NIR/facts/plans -> LIR boundary:
    #{PhaseBoundarySpec.format(problems)}
    MESSAGE
  end

  it "no phase upstream of target/go names a concrete Go API" do
    problems = PhaseBoundarySpec.selector_leaks
    problems.should be_empty, <<-MESSAGE
    Only target/go may name Go APIs. A `package.Func` selector upstream (in code
    or a comment) is a backend detail that leaked into a target-blind phase —
    name the tango concept or move the knowledge into target/go:
    #{PhaseBoundarySpec.format(problems)}
    MESSAGE
  end
end

# Vocabulary scans catch direct leaks, while the require graph catches an
# upstream phase importing the same knowledge through an otherwise neutral
# helper. Only project-relative requires participate; shard/stdlib requires are
# outside Tango's phase graph.
module PhaseRequireGraphSpec
  ROOT = File.expand_path("..", __DIR__)

  BOUNDARIES = {
    "self-hosting core" => {
      "src/tango/core",
      %w(
        src/tango/frontend/crystal
        src/tango/frontend/source_graph
        src/tango/toolchain/crystal
        src/tango/compiler/driver
        src/tango/compiler/pipeline
        src/tango/cli
        src/tango/lsp
      ),
    },
    "frontend" => {
      "src/tango/frontend",
      %w(src/tango/ir/lir src/tango/analysis src/tango/planning src/tango/lowering src/tango/target),
    },
    "expansion" => {
      "src/tango/expansion",
      %w(src/tango/ir/lir src/tango/analysis src/tango/planning src/tango/lowering src/tango/target),
    },
    "nir" => {
      "src/tango/ir/nir",
      %w(src/tango/ir/lir src/tango/analysis src/tango/planning src/tango/lowering src/tango/target),
    },
    "analysis" => {
      "src/tango/analysis",
      %w(src/tango/ir/lir src/tango/planning src/tango/lowering src/tango/target),
    },
    "planning" => {
      "src/tango/planning",
      %w(src/tango/ir/lir src/tango/lowering src/tango/target),
    },
    "lowering" => {
      "src/tango/lowering",
      %w(src/tango/target),
    },
  }

  def self.project_path?(path : String) : Bool
    path == ROOT || path.starts_with?("#{ROOT}/")
  end

  def self.relative(path : String) : String
    path.lchop("#{ROOT}/")
  end

  def self.dependencies(path : String) : Array(String)
    absolute = File.join(ROOT, path)
    File.read(absolute).scan(/^require\s+"([^"]+)"/m).flat_map do |match|
      required = match[1]
      next [] of String unless required.starts_with?('.')

      base = File.expand_path(required, File.dirname(absolute))
      candidates = if required.includes?('*')
                     Dir.glob(base)
                   elsif File.file?(base)
                     [base]
                   elsif File.file?("#{base}.cr")
                     ["#{base}.cr"]
                   else
                     [] of String
                   end
      candidates.select { |candidate| File.file?(candidate) && project_path?(candidate) }.map { |candidate| relative(candidate) }
    end.uniq.sort
  end

  def self.graph : Hash(String, Array(String))
    result = {} of String => Array(String)
    Dir.glob(File.join(ROOT, "src", "**", "*.cr")).sort.each do |path|
      relative_path = relative(path)
      result[relative_path] = dependencies(relative_path)
    end
    result
  end

  def self.in_slice?(path : String, prefix : String) : Bool
    path == "#{prefix}.cr" || path.starts_with?("#{prefix}/")
  end

  def self.path_to_forbidden(start : String, forbidden : Array(String), graph : Hash(String, Array(String))) : Array(String)?
    pending = [[start]] of Array(String)
    seen = Set(String).new

    until pending.empty?
      path = pending.shift
      current = path.last
      next unless seen.add?(current)

      return path if current != start && forbidden.any? { |prefix| in_slice?(current, prefix) }
      (graph[current]? || [] of String).each { |dependency| pending << path + [dependency] }
    end
    nil
  end

  def self.violations : Array(String)
    project_graph = graph
    BOUNDARIES.flat_map do |name, boundary|
      prefix, forbidden = boundary
      project_graph.keys.select { |path| in_slice?(path, prefix) }.compact_map do |origin|
        path_to_forbidden(origin, forbidden, project_graph).try do |path|
          "#{name}: #{path.join(" -> ")}"
        end
      end
    end
  end
end

describe "phase require-graph guardrails" do
  it "detects a forbidden phase dependency reached through an indirect helper" do
    graph = {
      "src/upstream.cr" => ["src/helper.cr"],
      "src/helper.cr"   => ["src/target.cr"],
      "src/target.cr"   => [] of String,
    }

    PhaseRequireGraphSpec.path_to_forbidden("src/upstream.cr", ["src/target"], graph).should eq([
      "src/upstream.cr",
      "src/helper.cr",
      "src/target.cr",
    ])
  end

  it "keeps every upstream phase disconnected from downstream imports" do
    violations = PhaseRequireGraphSpec.violations
    violations.should be_empty, <<-MESSAGE
    Upstream phases must not import downstream implementation knowledge, even
    indirectly. Move the dependency to its owning phase or introduce a neutral
    upstream abstraction:
    #{violations.join('\n')}
    MESSAGE
  end
end

# Generated program logic is a closed, typed Go IR. Raw Go source belongs
# only to Runtime's named helper registries, where imports and dependencies are
# explicit and participate in requirement closure.
module GoEscapeHatchSpec
  ROOT = File.expand_path("..", __DIR__)

  def self.target_files : Array(String)
    Dir.glob(File.join(ROOT, "src/tango/target/go", "**", "*.cr")).sort
  end

  def self.raw_source_offenders : Array(String)
    target_files.compact_map do |path|
      runtime_registry = File.dirname(path) == File.join(ROOT, "src/tango/target/go/runtime") &&
                         File.basename(path).matches?(/^registry(?:_.+)?\.cr$/)
      next if runtime_registry
      text = File.read(path)
      next unless text.includes?("Snippet.new") || text.includes?("<<-GO")
      path.lchop("#{ROOT}/")
    end
  end

  def self.nodes(base : String) : Array(String)
    text = target_files.map { |path| File.read(path) }.join('\n')
    text.scan(/class (\w+) < (?:IR::)?#{base}/).map(&.[1]).sort
  end
end

describe "Go target escape-hatch guardrails" do
  it "keeps raw Go snippets inside the runtime registries" do
    offenders = GoEscapeHatchSpec.raw_source_offenders
    offenders.should be_empty, <<-MESSAGE
    Raw Go snippets are restricted to target/go/runtime/registry*.cr. Program
    logic must use the typed Go IR, and runtime helpers must be named registry
    entries with explicit requirements:
    #{offenders.join('\n')}
    MESSAGE
  end

  it "pins the typed Go statement and expression node set" do
    GoEscapeHatchSpec.nodes("Stmt").should eq(%w(
      AssignStmt BranchStmt DeferStmt ExprStmt ForStmt GoStmt IfStmt
      LineDirective MultiAssignStmt RangeStmt ReturnStmt SelectStmt SendStmt
      Switch VarDecl
    ).sort)
    GoEscapeHatchSpec.nodes("Expr").should eq(%w(
      AddrOf Binary BitNot BoolLit Call CompositeLit Deref FloatLit FuncLit
      GenericInst Ident Index IntLit MakeChan Not RecvExpr Selector StringLit
      TypeAssert
    ).sort)
  end
end

# Node inventory: pins the exact NIR/LIR node set. Nodes are added deliberately, one
# driving example at a time; a node
# appearing here that isn't in the pinned list means it landed without that
# same-change update, which is the tripwire this test exists to catch.
describe "NIR/LIR node inventory" do
  it "pins the exact set of NIR node classes" do
    root = File.expand_path("..", __DIR__)
    text = Dir.glob(File.join(root, "src/tango/ir/nir", "**", "*.cr")).sort.map { |f| File.read(f) }.join('\n')

    exprs = text.scan(/class (\w+) < (?:Expr|NamedExpr|Literal|HashExpr|ArrayOperation|StringOperation|SemanticOperation|SemanticCollectionOperation|IndexedOperation)/).map(&.[1]).reject { |name| name.in?("NamedExpr", "Literal", "HashExpr", "ArrayOperation", "StringOperation", "SemanticOperation", "SemanticCollectionOperation", "IndexedOperation") }.sort
    stmts = text.scan(/class (\w+) < (?:Stmt|ControlExit)/).map(&.[1]).reject { |name| name == "Expr" || name == "ControlExit" }.sort

    exprs.should eq %w(ArrayBuild ArrayGet ArrayNew ArrayPush ArraySet Assign BlockLiteral BoolLiteral Call Cast ChannelNew ChannelOp ClassRef CollectionEach CollectionFilter CollectionFold CollectionMap ConstantReference EnumMember ExceptionHandler ExceptionNew FloatLiteral HashFetch HashGet HashHasKey HashKeyAt HashNew HashSet If IndexedRead IndexedWrite InstanceVar IntLiteral Interpolation InvokeBlock Local MutexNew New NilLiteral Not Raise Select Size Spawn StringCharAt StringEachChar StringLiteral StringSplit StringToFloat StringToInteger TypeTest UnsupportedExpr ValueSequence).sort
    stmts.should eq %w(Block BlockArg BlockParam Break Class Constant Def Enum FieldInitializer Namespace Next Param Return TypeAlias TypeAliasReference While).sort
  end

  it "keeps the semantic-bundle codec exhaustive with the NIR inventory" do
    root = File.expand_path("..", __DIR__)
    nir = Dir.glob(File.join(root, "src/tango/ir/nir", "**", "*.cr")).sort.map { |f| File.read(f) }.join('\n')
    encoder = File.read(File.join(root, "src/tango/frontend/bundle/codec/nir_encoder.cr"))
    decoder = File.read(File.join(root, "src/tango/frontend/bundle/codec/nir_decoder.cr"))

    exprs = nir.scan(/class (\w+) < (?:Expr|NamedExpr|Literal|HashExpr|ArrayOperation|StringOperation|SemanticOperation|SemanticCollectionOperation|IndexedOperation)/).map(&.[1]).reject { |name| name.in?("NamedExpr", "Literal", "HashExpr", "ArrayOperation", "StringOperation", "SemanticOperation", "SemanticCollectionOperation", "IndexedOperation") }
    stmts = nir.scan(/class (\w+) < (?:Stmt|ControlExit)/).map(&.[1]).reject { |name| name == "Expr" || name == "ControlExit" }
    expected_tags = (exprs + stmts).map do |name|
      name.gsub(/([a-z0-9])([A-Z])/, "\\1_\\2").downcase
    end.sort

    encoder_tags = encoder.split("private def kind", 2).last.scan(/then "([a-z_]+)"/).map(&.[1]).sort
    decoder_branches = decoder.split("private def expected_fields", 2).last
    decoder_tags = decoder_branches.lines
      .select { |line| line.lstrip.starts_with?("when ") }
      .flat_map { |line| line.scan(/"([a-z_]+)"/).map(&.[1]) }
      .sort

    encoder_tags.should eq(expected_tags)
    decoder_tags.should eq(expected_tags)
  end

  it "pins the exact set of LIR node classes" do
    root = File.expand_path("..", __DIR__)
    text = Dir.glob(File.join(root, "src/tango/ir/lir", "**", "*.cr")).sort.map { |f| File.read(f) }.join('\n')
    dump = File.read(File.join(root, "src/tango/dump/lir.cr"))

    values = text.scan(/class (\w+) < (?:Value|HashValue|ArrayOperation|ChannelReceiveValue|BinaryValue|NumericConst|NumericConvert|CarrierValue\([^\)]+\)|DispatchRelationValue\(\w+\))/).map(&.[1]).reject { |name| name.in?("HashValue", "ArrayOperation", "ChannelReceiveValue", "BinaryValue", "NumericConst", "CarrierValue", "DispatchRelationValue") }.sort
    stmts = text.scan(/class (\w+) < Stmt/).map(&.[1]).sort

    values.should eq %w(AddressOf Alloc ArrayBuild ArrayGet ArrayNew ArrayPush ArraySet Binary BoolConst Box Call Cast ChanReceive ChanReceiveMaybe ChanReceiveMaybeBox ChanReceiveState CheckedArithmetic Closure CollectionCount EnumConst ExceptionValue ExternalCallValue FieldAccess FloatArithmetic FloatConst FloatIntrinsic FloatToIntegerConvert FloorArithmetic FusedCollectionTraversal GlobalRef HashFetch HashGet HashHasKey HashKeyAt HashNew HashSet IfValue IntConst IntegerBitNot IntegerConvert IntegerNegate IntegerOperationValue Interpolation InvokeClosure MakeChan MakeMutex MaterializedStringSplit NilCheck NilConst NilValue Not NumericConvert RescueValue ScalarStringify StringCharAt StringCompare StringConst StringToFloat StringToInteger Temp TypeTest Unbox UnsupportedValue ValueSequence Widen).sort
    stmts.should eq %w(AbruptExit Assign ChanClose ChanSend Discard ExternalCall FieldAssign Handler If Select Spawn StringEachChar UnsupportedStmt While).sort

    rendered = dump.scan(/when IR::LIR::(\w+)/).map(&.[1]).uniq
    (values - rendered).should be_empty, "LIR dump is missing value renderers: #{(values - rendered).join(", ")}"
    (stmts - rendered).should be_empty, "LIR dump is missing statement renderers: #{(stmts - rendered).join(", ")}"
  end
end

# Adding a fact or plan table is incomplete until its phase dump names it.
# This is intentionally source-shaped like the LIR inventory above: a new
# getter/property changes the inventory immediately, before a fixture can
# accidentally normalize its invisibility.
module PhaseDumpCoverageSpec
  ROOT = File.expand_path("..", __DIR__)

  def self.table_fields(path : String) : Array(String)
    text = File.read(File.join(ROOT, path))
    table = text.split("class Table", 2)[1]? || ""
    table.scan(/^\s+(?:getter|property)\s+(\w+)/m).map(&.[1]).uniq.sort
  end

  def self.dumped_fields(path : String, receiver : String) : Array(String)
    File.read(File.join(ROOT, path)).scan(/\b#{receiver}\.(\w+)/).map(&.[1]).uniq.sort
  end
end

describe "Facts/Plans dump coverage" do
  it "renders every Facts::Table surface" do
    fields = PhaseDumpCoverageSpec.table_fields("src/tango/analysis/facts.cr")
    dumped = PhaseDumpCoverageSpec.dumped_fields("src/tango/dump/facts.cr", "facts")
    (fields - dumped).should be_empty, "Facts dump is missing table fields: #{(fields - dumped).join(", ")}"
  end

  it "renders every Plans::Table surface" do
    fields = PhaseDumpCoverageSpec.table_fields("src/tango/planning/plans.cr")
    dumped = PhaseDumpCoverageSpec.dumped_fields("src/tango/dump/plans.cr", "plans")
    (fields - dumped).should be_empty, "Plans dump is missing table fields: #{(fields - dumped).join(", ")}"
  end
end
