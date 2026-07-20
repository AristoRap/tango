require "../spec_helper"

private EXAMPLES_DIR = File.expand_path("../../examples", __DIR__)
private GOLDEN_DIR   = __DIR__

# Examples whose behavior is a non-zero exit / data race, asserted by
# `race_spec.cr` instead — they have no deterministic stdout to pin here.
private NEGATIVE = %w(race_counter uncaught_exception)

describe "golden examples" do
  Dir.glob(File.join(EXAMPLES_DIR, "*.tn")).sort.each do |source_path|
    name = File.basename(source_path, ".tn")
    next if NEGATIVE.includes?(name)
    golden_path = File.join(GOLDEN_DIR, "#{name}.stdout")

    it "runs examples/#{name}.tn and matches spec/golden/#{name}.stdout" do
      File.exists?(golden_path).should be_true

      go_source = Tango.compile(File.read(source_path), filename: source_path)

      output = IO::Memory.new
      error = IO::Memory.new
      result = Tango::Toolchain::Go.run_source(go_source, source_path, output, error)

      error.to_s.should be_empty
      result.status.should eq(0)
      result.diagnostics.should be_empty
      output.to_s.should eq(File.read(golden_path))
    end
  end
end
