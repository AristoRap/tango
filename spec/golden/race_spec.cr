require "../spec_helper"

private EXAMPLES_DIR = File.expand_path("../../examples", __DIR__)

# The negative-path counterpart to the positive golden harness: an
# intentionally-unguarded shared counter, run under `--race`, must trip the
# detector. Two goroutines each do 100k unsynchronized increments, so detection
# is effectively deterministic. A build failure (no cgo/C toolchain) surfaces
# here too — the assertion shows the actual stderr rather than passing silently.
describe "race detection" do
  it "trips the race detector on examples/race_counter.tn under --race" do
    source_path = File.join(EXAMPLES_DIR, "race_counter.tn")
    go_source = Tango.compile(File.read(source_path), filename: source_path)

    output = IO::Memory.new
    error = IO::Memory.new
    result = Tango::Toolchain::Go.run_source(go_source, source_path, output, error, race: true)

    result.status.should_not eq(0)
    result.diagnostics.should be_empty
    error.to_s.should contain("DATA RACE")
  end
end
