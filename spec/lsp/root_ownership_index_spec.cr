require "../spec_helper"
require "../../src/tango/lsp"

private def with_ownership_workspace(name : String, files : Hash(String, String), &)
  root = File.join(Dir.tempdir, "tango-lsp-ownership-#{name}-#{Process.pid}-#{Random.rand(100_000)}")
  Dir.mkdir_p(root)
  files.each do |relative, source|
    path = File.join(root, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
  end
  yield root
ensure
  FileUtils.rm_rf(root) if root
end

describe Tango::Lsp::RootOwnershipIndex do
  it "selects the unique top-level owner from a cached reverse require index" do
    with_ownership_workspace("unique", {
      "tango.json"       => %({"entrypoints":["main.tn"]}),
      "main.tn"          => "require \"./support/value\"\nputs value\n",
      "support/value.tn" => "def value : Int32\n  1\nend\n",
    }) do |root|
      dependency = File.join(root, "support", "value.tn")
      workspace = Tango::Lsp::Workspace.new(IO::Memory.new, debounce: Time::Span.zero)
      workspace.configure_roots([root])
      workspace.open("file://#{dependency}", dependency, File.read(dependency), 1)

      workspace.analysis_requests.last.root_path.should eq(Tango::Source::File.canonical_identity(File.join(root, "main.tn")))
    ensure
      workspace.try(&.stop)
    end
  end

  it "does not attach a shared dependency to an arbitrary application root" do
    with_ownership_workspace("ambiguous", {
      "tango.json" => %({"entrypoints":["alpha.tn","beta.tn"]}),
      "alpha.tn"   => "require \"./shared\"\nputs value\n",
      "beta.tn"    => "require \"./shared\"\nputs value\n",
      "shared.tn"  => "def value : Int32\n  1\nend\n",
    }) do |root|
      dependency = File.join(root, "shared.tn")
      workspace = Tango::Lsp::Workspace.new(IO::Memory.new, debounce: Time::Span.zero)
      workspace.configure_roots([root])
      workspace.open("file://#{dependency}", dependency, File.read(dependency), 1)

      workspace.analysis_requests.last.root_path.should eq(dependency)
    ensure
      workspace.try(&.stop)
    end
  end

  it "ignores unlisted top-level files when assigning ownership" do
    with_ownership_workspace("unlisted", {
      "tango.json"    => %({"entrypoints":["main.tn"]}),
      "main.tn"       => "require \"./shared\"\nputs value\n",
      "incidental.tn" => "require \"./shared\"\nputs value\n",
      "shared.tn"     => "def value : Int32\n  1\nend\n",
    }) do |root|
      index = Tango::Lsp::RootOwnershipIndex.new(IO::Memory.new)
      index.rebuild([root])

      index.unique_owner?(File.join(root, "shared.tn")).should eq(
        Tango::Source::File.canonical_identity(File.join(root, "main.tn"))
      )
    end
  end

  it "does not infer a disk owner without a manifest" do
    with_ownership_workspace("no-manifest", {
      "main.tn"   => "require \"./shared\"\nputs value\n",
      "shared.tn" => "def value : Int32\n  1\nend\n",
    }) do |root|
      index = Tango::Lsp::RootOwnershipIndex.new(IO::Memory.new)
      index.rebuild([root])

      index.unique_owner?(File.join(root, "shared.tn")).should be_nil
    end
  end

  it "logs a malformed manifest and leaves ownership unassigned" do
    with_ownership_workspace("malformed", {
      "tango.json" => %({"entrypoints":"main.tn"}),
      "main.tn"    => "puts 1\n",
    }) do |root|
      log = IO::Memory.new
      index = Tango::Lsp::RootOwnershipIndex.new(log)
      index.rebuild([root])

      index.unique_owner?(File.join(root, "main.tn")).should be_nil
      manifest = Tango::Source::File.canonical_identity(File.join(root, "tango.json"))
      log.to_s.should contain("invalid #{manifest}")
      log.to_s.should contain("expected an entrypoints array")
    end
  end

  it "rejects invalid entrypoint paths transactionally" do
    with_ownership_workspace("invalid-paths", {
      "tango.json" => %({"entrypoints":["main.tn"]}),
      "main.tn"    => "puts 1\n",
      "helper.cr"  => "puts 2\n",
    }) do |root|
      manifest = File.join(root, "tango.json")
      invalid = {
        File.join(root, "main.tn") => "must be a relative path",
        "../outside.tn"            => "escapes the workspace root",
        "helper.cr"                => "must name a .tn file",
        "missing.tn"               => "does not exist",
      }

      invalid.each do |request, message|
        File.write(manifest, {entrypoints: ["main.tn", request]}.to_json)
        log = IO::Memory.new
        index = Tango::Lsp::RootOwnershipIndex.new(log)
        index.rebuild([root])

        index.unique_owner?(File.join(root, "main.tn")).should be_nil
        log.to_s.should contain(message)
      end
    end
  end
end
