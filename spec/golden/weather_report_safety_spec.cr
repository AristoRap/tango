require "../spec_helper"

private WEATHER_APP      = File.expand_path("../../examples/weather_report.tn", __DIR__)
private WEATHER_DATA     = "examples/data/weather_measurements.txt"
private WEATHER_FIXTURES = File.expand_path("../fixtures/weather_report", __DIR__)

private def run_weather_source(source : String)
  output = IO::Memory.new
  error = IO::Memory.new
  go_source = Tango.compile(source, filename: WEATHER_APP)
  result = Tango::Toolchain::Go.run_source(go_source, WEATHER_APP, output, error)
  {result, output.to_s, error.to_s}
end

describe "weather report safety" do
  it "keeps File.read failures typed and rescuable through Crystal's hierarchy" do
    missing = File.join(WEATHER_FIXTURES, "missing.txt")
    source = <<-TN
      require "tango/fs"

      begin
        File.read("#{missing}")
      rescue ex : File::NotFoundError
        puts ex.message
      end

      begin
        File.read("#{missing}")
      rescue ex : File::Error
        puts "file ancestor"
      end

      begin
        File.read("#{WEATHER_FIXTURES}")
      rescue ex : IO::Error
        puts "io ancestor"
      end
      TN

    result, output, error = run_weather_source(source)

    result.status.should eq(0)
    result.diagnostics.should be_empty
    error.should be_empty
    output.should eq("Error opening file with mode 'r': '#{missing}': No such file or directory\nfile ancestor\nio ancestor\n")
  end

  it "fails every reachable complete-application edge with a typed source location" do
    base = File.read(WEATHER_APP)
    missing = File.join(WEATHER_FIXTURES, "missing.txt")
    cases = [
      {
        name:     "missing file",
        source:   base.sub(WEATHER_DATA, missing),
        first:    "Unhandled exception: Error opening file with mode 'r': '#{missing}': No such file or directory (File::NotFoundError)",
        location: "File.read",
      },
      {
        name:     "empty data",
        source:   base.sub(WEATHER_DATA, File.join(WEATHER_FIXTURES, "empty.txt")),
        first:    "Unhandled exception: No weather records (ArgumentError)",
        location: "No weather records",
      },
      {
        name:     "malformed record",
        source:   base.sub(WEATHER_DATA, File.join(WEATHER_FIXTURES, "malformed.txt")),
        first:    "Unhandled exception: Malformed weather record (ArgumentError)",
        location: "Malformed weather record",
      },
      {
        name:     "invalid number",
        source:   base.sub(WEATHER_DATA, File.join(WEATHER_FIXTURES, "invalid_number.txt")),
        first:    %(Unhandled exception: Invalid Float64: "not-a-number" (ArgumentError)),
        location: ".to_f",
      },
      {
        name:   "count overflow",
        source: base
          .sub(WEATHER_DATA, File.join(WEATHER_FIXTURES, "overflow.txt"))
          .sub("@count = 1", "@count = 2147483647"),
        first:    "Unhandled exception: Arithmetic overflow (OverflowError)",
        location: "@count = @count + 1",
      },
    ]

    cases.each do |test_case|
      result, output, error = run_weather_source(test_case[:source])
      line = test_case[:source].lines.index!(&.includes?(test_case[:location])) + 1

      result.status.should eq(1), test_case[:name]
      result.diagnostics.should be_empty, test_case[:name]
      output.should be_empty, test_case[:name]
      error.lines.first.rstrip.should eq(test_case[:first]), test_case[:name]
      error.should contain("#{WEATHER_APP}:#{line}"), test_case[:name]
      error.should_not contain("recovered, repanicked"), test_case[:name]
    end
  end
end
