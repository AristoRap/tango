require "./spec_helper"

# These are semantic-duplication ratchets, not a blanket DRY rule. Compiler
# phases intentionally repeat some vocabulary in distinct representations.
# Every repeated structural shape above the thresholds below must nevertheless
# be reviewed and classified. A new unclassified shape fails the suite.
module DuplicationGuardrails
  ROOT = File.expand_path("..", __DIR__)

  record Review, members : Array(String), disposition : Symbol, reason : String

  class Shape
    getter file : String
    getter name : String
    getter indent : Int32
    getter fields = [] of String
    getter collections = Set(String).new
    getter saved_fields = Set(String).new

    def initialize(@file : String, @name : String, @indent : Int32)
    end

    def id : String
      "#{file}##{name}"
    end
  end

  REPEATED_FIELD_PAIRS = {
    "src/tango/ir/lir/program.cr|name+type"              => Review.new(%w(Global Param StructType UnionType), :intentional, "Typed LIR declarations preserve both target names and language identity."),
    "src/tango/ir/lir/program.cr|reference+type"         => Review.new(%w(ArrayType HashType StructType), :intentional, "Representation descriptors pair concrete type identity with reference policy."),
    "src/tango/ir/lir/value.cr|source+value"             => Review.new(%w(DispatchRelationValue NumericConvert ScalarStringify), :intentional, "Distinct operation wrappers retain their typed input and source relation."),
    "src/tango/ir/lir/value.cr|hash+key"                 => Review.new(%w(HashFetch HashGet HashHasKey HashSet), :debt, "Keyed hash operations repeat receiver and key state; review a shared shape when this family grows."),
    "src/tango/ir/nir/hash.cr|hash+key"                  => Review.new(%w(HashFetch HashGet HashHasKey HashSet), :debt, "Keyed hash operations repeat receiver and key state; review a shared shape when this family grows."),
    "src/tango/planning/plans.cr|reference+type"         => Review.new(%w(ArrayRepr Constructor HashRepr), :intentional, "Each representation plan pairs its language type with a reference policy."),
    "src/tango/ir/nir/call.cr|name+name_span"            => Review.new(%w(BlockArg BlockParam Call), :intentional, "Named syntax nodes retain both semantic names and precise source spans."),
    "src/tango/ir/nir/namespace.cr|name_span+path"       => Review.new(%w(Constant ConstantReference Namespace TypeAlias TypeAliasReference), :intentional, "Namespace-owned declarations and references retain segmented identity plus their exact source token."),
    "src/tango/lsp/analysis_codec.cr|documentation+name" => Review.new(%w(DeclarationData SurfaceDeclarationData SurfaceParameterData), :intentional, "Serialized editor declarations carry display names and documentation independently."),
    "src/tango/lsp/analysis_codec.cr|kind+range"         => Review.new(%w(OccurrenceData SemanticTokenData SurfaceDeclarationData SurfaceScopeData), :intentional, "Serialized editor facts need both source ranges and protocol-specific kinds."),
  }

  CROSS_CLASS_FIELD_CLUSTERS = {
    "src/tango/ir/lir/program.cr#Func <> src/tango/ir/nir/def.cr#Def"                                           => Review.new(%w(body name params return_type), :intentional, "Callable structure is represented explicitly on both sides of lowering."),
    "src/tango/ir/lir/program.cr#Func <> src/tango/target/go/ir.cr#Func"                                        => Review.new(%w(body name params return_type), :intentional, "Structured target functions mirror the callable shape they emit."),
    "src/tango/ir/lir/program.cr#StructType <> src/tango/planning/plans.cr#ClassLayout"                         => Review.new(%w(exception_ancestors fields identity_padding name reference), :intentional, "Planning and LIR expose adjacent views of the same committed class layout."),
    "src/tango/ir/lir/program.cr#EnumType <> src/tango/planning/plans.cr#EnumRepr"                              => Review.new(%w(base_type members target_name type), :intentional, "Planning selects enum representation data and LIR copies the complete commitment for target-only consumption."),
    "src/tango/ir/lir/stmt.cr#Arm <> src/tango/ir/nir/concurrency.cr#ChannelOperation"                          => Review.new(%w(channel element kind value), :intentional, "Concurrency operations retain the same semantic payload across lowering."),
    "src/tango/ir/nir/def.cr#Def <> src/tango/target/go/ir.cr#Func"                                             => Review.new(%w(body name params return_type), :intentional, "Language and target callables intentionally keep parallel typed signatures."),
    "src/tango/ir/nir/def.cr#Def <> src/tango/lsp/analysis_codec.cr#MethodSiteData"                             => Review.new(%w(name name_span owner return_type), :intentional, "Editor method-site data serializes the definition identity needed by clients."),
    "src/tango/ir/type.cr#Type <> src/tango/lsp/analysis_codec.cr#TypeData"                                     => Review.new(%w(family members name type_args width), :intentional, "The editor codec provides a transport representation of structured types."),
    "src/tango/lsp/analysis_codec.cr#DeclarationData <> src/tango/lsp/analysis_codec.cr#SurfaceDeclarationData" => Review.new(%w(documentation name range visibility), :intentional, "Semantic and syntax-surface declarations serve different recovery states."),
    "src/tango/lsp/analysis_codec.cr#FileData <> src/tango/source/file.cr#File"                                 => Review.new(%w(code identity path stable_path), :intentional, "The worker codec transports immutable source-file identity and contents."),
    "src/tango/lsp/analysis_codec.cr#Payload <> src/tango/source/compilation_unit.cr#CompilationUnit"           => Review.new(%w(edges entrypoint files requires), :intentional, "The worker payload serializes the compilation-unit graph."),
  }

  COLLECTION_STATE_DEBT = {} of String => Review

  MANUAL_SCOPE_DEBT = {} of String => Review

  REPEATED_RECORD_SHAPES = {
    "name+type"                                            => Review.new(%w(src/tango/compiler/editor/hover.cr#ConstantSubject src/tango/compiler/editor/index.cr#Parameter src/tango/ir/type.cr#Field), :intentional, "Small named typed values are independent domain records."),
    "label+payload+tag"                                    => Review.new(%w(src/tango/ir/lir/program.cr#Variant src/tango/planning/plans.cr#Variant), :intentional, "Planned and committed union variants preserve the same identity."),
    "name+type_name"                                       => Review.new(%w(src/tango/target/go/ir.cr#Field src/tango/target/go/ir.cr#Receiver), :intentional, "Go fields and receivers independently require a name and rendered type."),
    "name+value"                                           => Review.new(%w(src/tango/analysis/facts.cr#EnumMember src/tango/target/go/ir.cr#Member), :intentional, "Semantic enum members and typed Go constants independently retain a name and integer literal."),
    "name+target_name+value"                               => Review.new(%w(src/tango/ir/lir/program.cr#Member src/tango/planning/plans.cr#Member), :intentional, "Planned and committed enum members preserve semantic and target identities across the lowering boundary."),
    "argument_types+kind+name+name_span+owner+return_type" => Review.new(%w(src/tango/compiler/editor/index.cr#CallableSite src/tango/ir/nir/expr.cr#MethodSite), :intentional, "The editor index retains a transport-friendly copy of resolved callable sites."),
  }

  def self.source_files : Array(String)
    Dir.glob(File.join(ROOT, "src/tango/**/*.cr")).sort
  end

  def self.shapes : Array(Shape)
    result = [] of Shape

    source_files.each do |path|
      relative = path.lchop("#{ROOT}/")
      stack = [] of Shape

      File.each_line(path) do |line|
        indent = line.size - line.lstrip.size

        if line.strip == "end" && (shape = stack.last?) && indent == shape.indent
          result << stack.pop
          next
        end

        if match = line.match(/^\s*(?:(?:private|abstract)\s+)*class\s+(\w+)/)
          stack << Shape.new(relative, match[1], indent)
          next
        end

        next unless shape = stack.last?

        if indent == shape.indent + 2 && (match = line.match(/^\s*(?:getter|property)\??\s+(\w+)\s*:/))
          shape.fields << match[1]
        end
        if match = line.match(/@(\w+)\s*=\s*(?:\[\]|\{\}|Set\(|Hash\()/)
          shape.collections << match[1]
        elsif match = line.match(/^\s*(?:getter|property)\??\s+(\w+)\s*=\s*(?:\[\]|\{\}|Set\(|Hash\()/)
          shape.collections << match[1]
        end
        if match = line.match(/saved\w*\s*=\s*@(\w+)/)
          shape.saved_fields << match[1]
        end
      end
    end

    result
  end

  def self.record_shapes : Array(Shape)
    result = [] of Shape

    source_files.each do |path|
      relative = path.lchop("#{ROOT}/")
      lines = File.read(path).lines
      lines.each_with_index do |line, index|
        match = line.match(/^(\s*)record\s+(\w+)(?:\s*<[^,]+)?,(.*)$/)
        next unless match

        indent = match[1].size
        shape = Shape.new(relative, match[2], indent)
        match[3].scan(/(\w+)\s*:(?!:)/).each { |field| shape.fields << field[1] }

        cursor = index + 1
        while cursor < lines.size && lines[cursor].size - lines[cursor].lstrip.size > indent
          field = lines[cursor].match(/^\s*(\w+)\s*:(?!:)/)
          break unless field

          shape.fields << field[1]
          cursor += 1
        end
        result << shape unless shape.fields.empty?
      end
    end

    result
  end

  def self.repeated_field_pairs(shapes : Array(Shape)) : Hash(String, Array(String))
    groups = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }

    shapes.each do |shape|
      fields = shape.fields.uniq.sort
      fields.each_with_index do |left, index|
        fields[(index + 1)..].each do |right|
          groups["#{shape.file}|#{left}+#{right}"] << shape.name
        end
      end
    end

    groups.compact_map do |key, classes|
      unique = classes.uniq.sort
      unique.size >= 3 ? {key, unique} : nil
    end.to_h
  end

  def self.cross_class_clusters(shapes : Array(Shape)) : Hash(String, Array(String))
    groups = {} of String => Array(String)

    shapes.each_with_index do |left, index|
      shapes[(index + 1)..].each do |right|
        common = (left.fields.uniq & right.fields.uniq).sort
        next unless common.size >= 4

        ids = [left.id, right.id].sort
        groups["#{ids[0]} <> #{ids[1]}"] = common
      end
    end

    groups
  end

  def self.repeated_record_shapes(shapes : Array(Shape)) : Hash(String, Array(String))
    groups = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
    shapes.each do |shape|
      fields = shape.fields.uniq.sort
      groups[fields.join('+')] << shape.id if fields.size >= 2
    end

    groups.compact_map do |fields, records|
      unique = records.uniq.sort
      unique.size >= 2 ? {fields, unique} : nil
    end.to_h
  end

  def self.collection_state_debt(shapes : Array(Shape)) : Hash(String, Array(String))
    shapes.compact_map do |shape|
      next if shape.name.matches?(/(?:Facts|Table|Index|Registry|Speller|Context|State|Environment)$/)
      fields = shape.collections.to_a.sort
      fields.size >= 3 ? {shape.id, fields} : nil
    end.to_h
  end

  def self.manual_scope_debt(shapes : Array(Shape)) : Hash(String, Array(String))
    shapes.compact_map do |shape|
      next if shape.name.matches?(/(?:Context|State)$/)
      fields = shape.saved_fields.to_a.sort
      fields.size >= 2 ? {shape.id, fields} : nil
    end.to_h
  end

  def self.reviewed(entries : Hash(String, Review)) : Hash(String, Array(String))
    entries.transform_values { |review| review.members.sort }
  end

  def self.reviews : Array(Review)
    REPEATED_FIELD_PAIRS.values +
      CROSS_CLASS_FIELD_CLUSTERS.values +
      REPEATED_RECORD_SHAPES.values +
      COLLECTION_STATE_DEBT.values +
      MANUAL_SCOPE_DEBT.values
  end
end

describe "semantic duplication ratchets" do
  shapes = DuplicationGuardrails.shapes

  it "classifies every field pair repeated across three sibling classes" do
    DuplicationGuardrails.repeated_field_pairs(shapes).should eq(
      DuplicationGuardrails.reviewed(DuplicationGuardrails::REPEATED_FIELD_PAIRS)
    )
  end

  it "classifies every four-field overlap between data classes" do
    DuplicationGuardrails.cross_class_clusters(shapes).should eq(
      DuplicationGuardrails.reviewed(DuplicationGuardrails::CROSS_CLASS_FIELD_CLUSTERS)
    )
  end

  it "classifies every record shape declared more than once" do
    DuplicationGuardrails.repeated_record_shapes(DuplicationGuardrails.record_shapes).should eq(
      DuplicationGuardrails.reviewed(DuplicationGuardrails::REPEATED_RECORD_SHAPES)
    )
  end

  it "keeps collection-heavy state in a named owner or an explicit debt review" do
    DuplicationGuardrails.collection_state_debt(shapes).should eq(
      DuplicationGuardrails.reviewed(DuplicationGuardrails::COLLECTION_STATE_DEBT)
    )
  end

  it "keeps manual multi-field dynamic scope in a context or an explicit debt review" do
    DuplicationGuardrails.manual_scope_debt(shapes).should eq(
      DuplicationGuardrails.reviewed(DuplicationGuardrails::MANUAL_SCOPE_DEBT)
    )
  end

  it "gives every reviewed repetition a disposition and rationale" do
    DuplicationGuardrails.reviews.each do |review|
      %i(intentional debt).should contain(review.disposition)
      review.reason.should_not be_empty
      review.reason.should_not match(/^\[[A-Z]\d+/)
    end
  end

  it "keeps Go run/build preparation behind one execution path" do
    source = File.read(File.join(DuplicationGuardrails::ROOT, "src/tango/toolchain/go.cr"))

    source.scan(/case prepared = prepare_execution/).size.should eq(1)
    source.scan(/Process\.run\(prepared\.toolchain\.path/).size.should eq(1)
  end
end

describe "target representation ownership" do
  target_root = File.join(DuplicationGuardrails::ROOT, "src/tango/target/go")
  files = Dir.glob(File.join(target_root, "**/*.cr")).sort

  it "keeps type-family, reference, and ordering interpretation in TypeSpeller" do
    policy = /\.family\b|\.reference\??\b|\.ordered\?\b/
    owners = files.select { |path| File.read(path).matches?(policy) }
      .map { |path| path.lchop("#{DuplicationGuardrails::ROOT}/") }

    owners.should eq(["src/tango/target/go/from_lir/type_speller.cr"])
  end

  it "keeps Array and Hash representation tables behind TypeSpeller" do
    direct_tables = /program\.(?:arrays|hashes)\b/
    owners = files.select { |path| File.read(path).matches?(direct_tables) }
      .map { |path| path.lchop("#{DuplicationGuardrails::ROOT}/") }

    owners.should eq(["src/tango/target/go/from_lir/type_speller.cr"])
  end

  it "reads the committed carrier nil tag through TypeSpeller, never a bare literal" do
    offenders = files.select { |path| File.read(path).includes?(%(IntLit.new("0"))) }
      .map { |path| path.lchop("#{DuplicationGuardrails::ROOT}/") }

    offenders.should be_empty, <<-MESSAGE
    A literal `IntLit.new("0")` reappeared in the Go target.  nil tag is
    only "0" by convention (Strategies::Repr#carrier assigns it) — read it via
    TypeSpeller#nil_tag instead of hardcoding the literal, or the assigned tag
    and the target's assumption about it can silently diverge:
    #{offenders.join('\n')}
    MESSAGE
  end
end

describe "builtin exception name list stays single-sourced" do
  to_nir = File.read(File.join(DuplicationGuardrails::ROOT, "src/tango/frontend/crystal/to_nir.cr"))
  helpers_src = File.read(File.join(DuplicationGuardrails::ROOT, "src/tango/target/go/builtin_exceptions.cr"))
  registry_src = File.read(File.join(DuplicationGuardrails::ROOT, "src/tango/target/go/runtime/registry.cr"))

  # Crystal exception name => Go helper, parsed from the shared table. Text-based
  # like the other ratchets, so the audit runs without loading the compiler.
  helper_pairs = helpers_src.scan(/"([^"]+)"\s*=>\s*"([^"]+)"/).map { |m| {m[1], m[2]} }

  it "keeps the frontend legality gate and the target helper table in agreement" do
    legality_block = expect_present(to_nir.match(/def builtin_exception\?.*?\n(.*?)\n\s*end\n/m))[1]
    legality = legality_block.scan(/"([^"]+)"/).map(&.[1]).sort

    helper_pairs.map(&.[0]).sort.should eq(legality), <<-MESSAGE
    `ToNIR#builtin_exception?`'s legality list (Crystal names) and
    `Target::Go::BUILTIN_EXCEPTION_HELPERS`'s keys must enumerate the same
    builtin-exception set. If a name is added to one without the other, the
    frontend either rejects a name the target can spell, or the target's
    `raise "unsupported builtin exception"` fallback becomes live for a name the
    frontend already accepted.
    frontend: #{legality}
    target:   #{helper_pairs.map(&.[0]).sort}
    MESSAGE
  end

  it "registers a runtime snippet for every builtin exception's Go helper" do
    exception_types = expect_present(registry_src.match(/BUILTIN_EXCEPTION_TYPES = begin(.*?)\n\s*SNIPPETS =/m))[1]
    registry_keys = exception_types.scan(/"(\w+)"\s*=>/).map(&.[1])
    missing = helper_pairs.map(&.[1]).reject { |helper| registry_keys.includes?(helper) }

    missing.should be_empty, <<-MESSAGE
    Every builtin exception's Go helper in `BUILTIN_EXCEPTION_HELPERS` must be
    generated by `Runtime::Registry::BUILTIN_EXCEPTION_TYPES` — otherwise
    emitting that exception needs a helper the registry can't resolve. The
    registry's keys are the third enumeration of the builtin set; this pins it
    to the shared table so it can't silently drop a helper.
    missing helpers: #{missing}
    MESSAGE
  end
end
