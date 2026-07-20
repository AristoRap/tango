require "../spec_helper"

private INTEGER_TYPES = {
  {"Int8", "1_i8", "to_i8"},
  {"UInt8", "1_u8", "to_u8"},
  {"Int16", "1_i16", "to_i16"},
  {"UInt16", "1_u16", "to_u16"},
  {"Int32", "1_i32", "to_i32"},
  {"UInt32", "1_u32", "to_u32"},
  {"Int64", "1_i64", "to_i64"},
  {"UInt64", "1_u64", "to_u64"},
}

private def integer_system_output(source : String) : {String, String}
  go_source = Tango.compile(source, filename: "integer_system_matrix.tn")
  output = IO::Memory.new
  error = IO::Memory.new
  result = Tango::Toolchain::Go.run_source(go_source, "integer_system_matrix.tn", output, error)

  error.to_s.should be_empty
  result.status.should eq(0), "stderr=#{error.to_s.inspect} diagnostics=#{result.diagnostics.map(&.message).inspect} output=#{output.to_s.inspect}"
  result.diagnostics.should be_empty
  {output.to_s, go_source}
end

describe "integer systems closure" do
  it "covers every supported width through one operation and conversion matrix" do
    source = String.build do |io|
      INTEGER_TYPES.each do |_type, literal, parser|
        io << "puts #{literal} <=> #{literal}\n"
        io << "puts #{literal} <= #{literal}\n"
        io << "puts #{literal} & #{literal}\n"
        io << "puts #{literal} | #{literal}\n"
        io << "puts #{literal} ^ #{literal}\n"
        io << "puts ~#{literal}\n"
        io << "puts #{literal} &+ #{literal}\n"
        io << "puts #{literal} &- #{literal}\n"
        io << "puts #{literal} &* #{literal}\n"
        io << %(puts "1".#{parser}\n)
        io << "puts #{literal}.to_i\n"
        io << "puts #{literal}.to_i!\n"
        io << "puts #{literal}.to_u\n"
        io << "puts #{literal}.to_u!\n"
        io << "puts #{literal}.to_f\n"
        io << "puts #{literal}.to_f64\n"
        io << "puts #{literal}.to_f64!\n"

        INTEGER_TYPES.each do |_count_type, count_literal, _count_parser|
          io << "puts #{literal} << #{count_literal}\n"
          io << "puts #{literal} >> #{count_literal}\n"
        end

        INTEGER_TYPES.each do |_target_type, _target_literal, target_method|
          io << "puts #{literal}.#{target_method}\n"
          io << "puts #{literal}.#{target_method}!\n"
        end
      end
    end

    output, go_source = integer_system_output(source)
    output.lines.size.should eq(INTEGER_TYPES.size * (17 + INTEGER_TYPES.size * 4))

    INTEGER_TYPES.each do |type, _literal, _parser|
      suffix = type.starts_with?("UInt") ? "U#{type.lchop("UInt")}" : "I#{type.lchop("Int")}"
      go_source.should contain("tangoWrappingAdd#{suffix}")
      go_source.should contain("tangoShiftLeft#{suffix}")
      go_source.should contain("tangoStringTo#{suffix}")
    end
  end

  it "pins signedness, narrowing, shift, and parser failure boundaries" do
    source = <<-TN
      begin
        puts -1_i8.to_u64
      rescue OverflowError
        puts "negative-to-unsigned"
      end
      begin
        puts 256_u16.to_u8
      rescue OverflowError
        puts "narrowing"
      end
      puts (-1_i8).to_u64!
      puts -8_i8 >> 2
      puts -8_i8 >> 8
      puts 8_i8 << -1
      puts "7f".to_i8(16)
      puts "128".to_i8?.nil?
      puts "-1".to_u64?.nil?
      TN

    output, _ = integer_system_output(source)
    output.should eq("negative-to-unsigned\nnarrowing\n18446744073709551615\n-2\n0\n4\n127\ntrue\ntrue\n")
  end
end
