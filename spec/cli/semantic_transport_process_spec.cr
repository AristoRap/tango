require "../spec_helper"
require "../../src/tango/cli"
require "../support/semantic_transport_process"

describe "the semantic-bundle process boundary" do
  it "emits byte-identical canonical Go through actual producer and consumer processes" do
    executable = Process.executable_path || raise "spec executable path is unavailable"
    source = File.expand_path("../../examples/string_split.tn", __DIR__)
    root = File.join(Dir.tempdir, "tango-semantic-process-#{Process.pid}-#{Random.rand(100_000)}")
    bundle = File.join(root, "program.json")
    Dir.mkdir_p(root)

    begin
      producer_output = IO::Memory.new
      producer_error = IO::Memory.new
      producer = Process.run(
        executable,
        output: producer_output,
        error: producer_error,
        env: {
          "TANGO_SPEC_SEMANTIC_PROCESS" => "producer",
          "TANGO_SPEC_SEMANTIC_SOURCE"  => source,
          "TANGO_SPEC_SEMANTIC_BUNDLE"  => bundle,
        }
      )
      producer.success?.should be_true, producer_error.to_s
      producer_output.to_s.should be_empty
      producer_error.to_s.should be_empty
      File.file?(bundle).should be_true

      transported = IO::Memory.new
      consumer_error = IO::Memory.new
      consumer = Process.run(
        executable,
        output: transported,
        error: consumer_error,
        env: {
          "TANGO_SPEC_SEMANTIC_PROCESS" => "consumer",
          "TANGO_SPEC_SEMANTIC_BUNDLE"  => bundle,
        }
      )
      consumer.success?.should be_true, consumer_error.to_s
      consumer_error.to_s.should be_empty

      ordinary = IO::Memory.new
      ordinary_error = IO::Memory.new
      in_process_command = Process.run(
        executable,
        output: ordinary,
        error: ordinary_error,
        env: {
          "TANGO_SPEC_SEMANTIC_PROCESS" => "ordinary",
          "TANGO_SPEC_SEMANTIC_SOURCE"  => source,
        }
      )
      in_process_command.success?.should be_true, ordinary_error.to_s
      ordinary_error.to_s.should be_empty
      transported.to_s.should eq(ordinary.to_s)
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
