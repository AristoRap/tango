require "../spec_helper"

private ERROR_FIXTURES = File.expand_path("errors", __DIR__)

describe "golden error fixtures" do
  Dir.glob(File.join(ERROR_FIXTURES, "*.tn")).sort.each do |source_path|
    name = File.basename(source_path, ".tn")
    fixture_path = File.join("spec", "golden", "errors", "#{name}.tn")
    golden_path = File.join(ERROR_FIXTURES, "#{name}.err")

    it "rejects #{fixture_path} with its exact diagnostic snapshot" do
      File.exists?(golden_path).should be_true

      source = File.read(source_path)
      snapshot = Tango.snapshot(source, filename: fixture_path)
      rendered = snapshot.diagnostics.map do |diagnostic|
        Tango::Diagnostics::Renderer.render(source, diagnostic, path: fixture_path)
      end.join('\n')

      rendered.should eq(File.read(golden_path).rstrip)
    end
  end
end
