require "./spec_helper"

describe "differential fuzzer harness" do
  it "passes its deterministic self-test" do
    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run("python3", ["scripts/fuzz.py", "--self-test"], output: output, error: error)

    status.success?.should be_true
    error.to_s.should be_empty
    output.to_s.should eq("fuzz harness self-test: ok\n")
  end
end
