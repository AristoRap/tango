require "../../spec_helper"

describe "Go filesystem runtime" do
  it "maps Go read failures into the committed Tango exception family" do
    source = Tango.compile(<<-TN, filename: "filesystem_runtime.tn")
      require "tango/fs"
      puts File.read("missing.txt")
      TN

    source.should contain("errors.Is(err, fs.ErrNotExist)")
    source.should contain("panic(&tangoFileNotFoundError")
    source.should contain("errors.Is(err, fs.ErrPermission)")
    source.should contain("panic(&tangoFileAccessDeniedError")
    source.should contain(%(pathError.Op == "read"))
    source.should contain("panic(&tangoIOError")
    source.should contain("panic(&tangoFileError")
    source.should_not contain("panic(err)")
    source.should contain(%(return name == "File::NotFoundError" || name == "File::Error" || name == "IO::Error" || name == "Exception"))
    source.should contain(%(return name == "File::AccessDeniedError" || name == "File::Error" || name == "IO::Error" || name == "Exception"))
  end

  it "lowers File.each_line to an unbounded buffered streaming leaf" do
    source = Tango.compile(<<-TN, filename: "filesystem_each_line.tn")
      require "tango/fs"
      File.each_line("measurements.txt") do |line|
        puts line
      end
      TN

    source.should contain(%(func tangoFileEachLine(path string, block func(string))))
    source.should contain("reader := bufio.NewReader(file)")
    source.should contain("reader.ReadString('\\n')")
    source.should contain("block(line)")
    source.should_not contain("bufio.NewScanner")
  end

  it "streams Crystal-compatible lines without a scanner token ceiling" do
    File.tempfile("tango-each-line") do |file|
      long_line = "x" * 70_000
      file.print("first\r\n", long_line, "\nlast")
      file.flush

      source = Tango.compile(<<-TN, filename: "filesystem_each_line_runtime.tn")
        require "tango/fs"
        File.each_line(#{file.path.inspect}) do |line|
          puts line
        end
        TN
      output = IO::Memory.new
      error = IO::Memory.new
      result = Tango::Toolchain::Go.run_source(source, "filesystem_each_line_runtime.tn", output, error)

      result.status.should eq(0)
      result.diagnostics.should be_empty
      error.to_s.should be_empty
      output.to_s.should eq("first\n#{long_line}\nlast\n")
    end
  end
end
