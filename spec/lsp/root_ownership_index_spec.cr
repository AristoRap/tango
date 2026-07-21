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
      "alpha.tn"  => "require \"./shared\"\nputs value\n",
      "beta.tn"   => "require \"./shared\"\nputs value\n",
      "shared.tn" => "def value : Int32\n  1\nend\n",
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
end
