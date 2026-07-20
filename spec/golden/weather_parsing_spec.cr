require "../spec_helper"

private def weather_parse_output(source : String) : String
  go_source = Tango.compile(source, filename: "weather_parsing.tn")
  output = IO::Memory.new
  error = IO::Memory.new
  result = Tango::Toolchain::Go.run_source(go_source, "weather_parsing.tn", output, error)

  error.to_s.should be_empty
  result.status.should eq(0)
  result.diagnostics.should be_empty
  output.to_s
end

describe "weather parsing" do
  it "raises a typed error for malformed records and invalid measurements" do
    source = <<-TN
      def weather_measurement(line : String) : Float64
        fields = line.split(";")
        raise ArgumentError.new("Malformed weather record") unless fields.size == 2
        fields[1].to_f
      end

      begin
        weather_measurement("Amsterdam")
      rescue ex : ArgumentError
        puts ex.message
      end

      begin
        weather_measurement("Amsterdam;1.0;unexpected")
      rescue ex : ArgumentError
        puts ex.message
      end

      begin
        weather_measurement("Amsterdam;nope")
      rescue ex : ArgumentError
        puts ex.message
      end
      TN

    weather_parse_output(source).should eq("Malformed weather record\nMalformed weather record\nInvalid Float64: \"nope\"\n")
  end
end
