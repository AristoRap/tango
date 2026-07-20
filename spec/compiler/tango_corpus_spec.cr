require "../spec_helper"

private PRODUCT_ROOTS = %w(examples stdlib)

describe "product Tango source corpus" do
  it "has no diagnostics and covers every product .tn through an owning graph" do
    entries = Dir.glob("examples/*.tn").sort
    packages = Dir.glob("stdlib/**/*.tn").sort
    covered = Set(String).new

    (entries + packages).each do |path|
      snapshot = Tango.pre_target_snapshot(File.read(path), filename: path)
      snapshot.diagnostics.should be_empty, "expected #{path} to compile without diagnostics:\n#{snapshot.diagnostics.join("\n")}"
      snapshot.source.files.each { |file| covered << File.expand_path(file.path) }
    end

    product_files = PRODUCT_ROOTS.flat_map { |root| Dir.glob(File.join(root, "**", "*.tn")) }
      .map { |path| File.expand_path(path) }
      .to_set
    uncovered = product_files - covered

    uncovered.should be_empty, "product Tango files need a diagnostic-clean owning entry graph: #{uncovered.to_a.sort.join(", ")}"
  end
end
