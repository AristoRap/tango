require "../spec_helper"

private FLOAT_INTEGER_TYPES = {
  {"Int8", "2_i8", "to_i8"},
  {"UInt8", "2_u8", "to_u8"},
  {"Int16", "2_i16", "to_i16"},
  {"UInt16", "2_u16", "to_u16"},
  {"Int32", "2_i32", "to_i32"},
  {"UInt32", "2_u32", "to_u32"},
  {"Int64", "2_i64", "to_i64"},
  {"UInt64", "2_u64", "to_u64"},
}

private def float_system_output(source : String) : {String, String}
  go_source = Tango.compile(source, filename: "float_system_matrix.tn")
  output = IO::Memory.new
  error = IO::Memory.new
  result = Tango::Toolchain::Go.run_source(go_source, "float_system_matrix.tn", output, error)

  error.to_s.should be_empty
  result.status.should eq(0), "stderr=#{error.to_s.inspect} diagnostics=#{result.diagnostics.map(&.message).inspect} output=#{output.to_s.inspect}"
  result.diagnostics.should be_empty
  {output.to_s, go_source}
end

describe "supported scalar arithmetic closure" do
  it "covers every integer/Float64 crossover, conversion, division, and power cell" do
    source = String.build do |io|
      FLOAT_INTEGER_TYPES.each do |_type, literal, conversion|
        io << "puts #{literal} + 0.5\n"
        io << "puts 0.5 + #{literal}\n"
        io << "puts #{literal} - 0.5\n"
        io << "puts 0.5 - #{literal}\n"
        io << "puts #{literal} * 0.5\n"
        io << "puts 0.5 * #{literal}\n"
        io << "puts #{literal} / 0.5\n"
        io << "puts 0.5 / #{literal}\n"
        %w(< <= > >= == != ===).each do |operator|
          io << "puts #{literal} #{operator} 2.5\n"
          io << "puts 2.5 #{operator} #{literal}\n"
        end
        io << "puts #{literal} // 0.5\n"
        io << "puts 5.0 % #{literal}\n"
        io << "puts 1.0.#{conversion}\n"
        io << "puts 2.0 ** #{literal}\n"
        io << "puts #{literal} ** 2.0\n"

        FLOAT_INTEGER_TYPES.each do |_other_type, other_literal, _other_conversion|
          io << "puts #{literal} / #{other_literal}\n"
          io << "puts #{literal} ** #{other_literal}\n"
          io << "puts #{literal} &** #{other_literal}\n"
        end
      end
    end

    output, go_source = float_system_output(source)
    output.lines.size.should eq(FLOAT_INTEGER_TYPES.size * (27 + FLOAT_INTEGER_TYPES.size * 3))
    output.lines.first(27).should eq(%w(2.5 2.5 1.5 -1.5 1.0 1.0 4.0 0.25 true false true false false true false true false false true true false false 4 1.0 1 4.0 4.0))

    FLOAT_INTEGER_TYPES.each do |type, _literal, _conversion|
      suffix = type.starts_with?("UInt") ? "U#{type.lchop("UInt")}" : "I#{type.lchop("Int")}"
      go_source.should contain("tangoPow#{suffix}")
      go_source.should contain("tangoWrappingPow#{suffix}")
      go_source.should contain("tangoConvertF64To#{suffix}")
    end
  end

  it "pins IEEE, checked-conversion, and integer-power boundaries" do
    source = <<-TN
      puts ((-0.0) ** 3).sign_bit
      puts ((-0.0) ** 2).sign_bit
      puts (-0.0) ** -3
      puts (0.0 / 0.0) ** 0
      puts 127.0.to_i8
      puts (-128.0).to_i8
      puts 9223372036854774784.0.to_i64
      puts 18446744073709549568.0.to_u64
      begin
        puts 127.9.to_i8
      rescue OverflowError
        puts "fractional upper edge"
      end
      begin
        puts 9223372036854775808.0.to_i64
      rescue OverflowError
        puts "signed 64 edge"
      end
      begin
        puts 18446744073709551616.0.to_u64
      rescue OverflowError
        puts "unsigned 64 edge"
      end
      begin
        puts (0.0 / 0.0).to_i32
      rescue OverflowError
        puts "nan conversion"
      end
      puts 2_i8 ** 0
      puts 2_i8 &** 7
      puts 2_i8 &** 8
      TN

    output, _ = float_system_output(source)
    output.should eq(<<-OUT + "\n")
      -1
      1
      -Infinity
      1.0
      127
      -128
      9223372036854774784
      18446744073709549568
      fractional upper edge
      signed 64 edge
      unsigned 64 edge
      nan conversion
      1
      -128
      0
      OUT
  end
end
