require "../spec_helper"

private def with_env(key : String, value : String?, &)
  previous = ENV[key]?

  if value
    ENV[key] = value
  else
    ENV.delete(key)
  end

  yield
ensure
  if previous
    ENV[key] = previous
  else
    ENV.delete(key)
  end
end

private def fake_toolchain(name : String, go_script : String, gofmt_script : String, &)
  root = File.join(Tango::Workspace::Layout.cache_dir, "spec-#{name}-#{Process.pid}-#{Random.rand(100_000)}")
  Dir.mkdir_p(root)

  go_path = File.join(root, "go")
  gofmt_path = File.join(root, "gofmt")

  File.write(go_path, go_script)
  File.write(gofmt_path, gofmt_script)
  File.chmod(go_path, 0o755)
  File.chmod(gofmt_path, 0o755)

  with_env("TANGO_GO", go_path) do
    yield go_path, gofmt_path
  end
end

private def version_script(rest : String) : String
  <<-SH
  #!/bin/sh
  if [ "$1" = "version" ]; then
    echo "go version go1.26.4 darwin/arm64"
    exit 0
  fi
  #{rest}
  SH
end

describe Tango::Toolchain::Go do
  it "formats source through the resolved gofmt before emit consumes it" do
    formatted = <<-GO
    package main

    func main() {
    \tfmt.Println(1)
    }
    GO

    fake_toolchain(
      "format",
      version_script("exit 1"),
      "#!/bin/sh\ncat >/dev/null\nprintf '%s' '#{formatted}'\n"
    ) do
      result = Tango::Toolchain::Go.format_source("package main\nfunc main(){fmt.Println(1)}\n")

      result.source.should eq(formatted)
      result.diagnostics.should be_empty
    end
  end

  it "returns a gofmt failure as shared check data" do
    fake_toolchain(
      "format-failure",
      version_script("exit 1"),
      "#!/bin/sh\ncat >/dev/null\necho 'gofmt detail' >&2\nexit 1\n"
    ) do
      result = Tango::Toolchain::Go.format_source("package main\nfunc main() {}\n")

      result.source.should be_nil
      result.diagnostics.size.should eq(1)
      diagnostic = result.diagnostics.first
      diagnostic.origin.check?.should be_true
      diagnostic.code.should eq(Tango::Diagnostics::CHECK_GOFMT)
      diagnostic.message.should eq("gofmt failed")
      expect_present(diagnostic.detail).should contain("gofmt detail")
    end
  end

  it "stops run and build before execution when shared preparation fails" do
    go_script = version_script(<<-SH)
    if [ "$1" = "vet" ]; then
      echo "$2:3:2: fmt.Printf format %d has arg \\"x\\" of wrong type string" >&2
      exit 1
    fi
    if [ "$1" = "run" ]; then
      exit 99
    fi
    exit 98
    SH

    fake_toolchain("vet", go_script, "#!/bin/sh\ncat\n") do
      output = IO::Memory.new
      error = IO::Memory.new

      result = Tango::Toolchain::Go.run_source(<<-GO, "spec_hygiene_vet.tn", output, error)
      package main

      import "fmt"

      func main() {
        fmt.Printf("%d", "x")
      }
      GO

      result.status.should eq(1)
      result.diagnostics.size.should eq(1)
      diagnostic = result.diagnostics.first
      diagnostic.origin.check?.should be_true
      diagnostic.code.should eq(Tango::Diagnostics::CHECK_GO_VET)
      expect_present(diagnostic.file).should start_with(Tango::Workspace::Layout.module_dir("spec_hygiene_vet.tn"))
      expect_present(diagnostic.file).should end_with("main.go")
      diagnostic.line.should eq(3)
      diagnostic.column.should eq(2)
      diagnostic.message.should contain("fmt.Printf format %d")
      output.to_s.should be_empty
      error.to_s.should be_empty

      build_error = IO::Memory.new
      build = Tango::Toolchain::Go.build_source(
        "package main\nfunc main() {}\n",
        "spec_hygiene_vet_build.tn",
        File.join(Tango::Workspace::Layout.cache_dir, "spec-vet-build-output"),
        build_error
      )

      build.status.should eq(1)
      build.diagnostics.size.should eq(1)
      build.diagnostics.first.code.should eq(Tango::Diagnostics::CHECK_GO_VET)
      build_error.to_s.should be_empty
    end
  end

  it "passes -race to go run only when race detection is requested" do
    go_script = version_script(<<-SH)
    if [ "$1" = "vet" ]; then exit 0; fi
    if [ "$1" = "run" ]; then echo "run-args:$@" >&2; exit 0; fi
    exit 98
    SH

    fake_toolchain("race", go_script, "#!/bin/sh\ncat\n") do
      raced = IO::Memory.new
      Tango::Toolchain::Go.run_source("package main\nfunc main() {}\n", "spec_race.tn", IO::Memory.new, raced, race: true)
      raced.to_s.should contain("-race")

      plain = IO::Memory.new
      Tango::Toolchain::Go.run_source("package main\nfunc main() {}\n", "spec_race.tn", IO::Memory.new, plain)
      plain.to_s.should_not contain("-race")
    end
  end

  it "prepares and vets source before building" do
    go_script = version_script(<<-SH)
    if [ "$1" = "vet" ]; then exit 0; fi
    if [ "$1" = "build" ]; then echo "build-args:$@" >&2; exit 0; fi
    exit 98
    SH

    fake_toolchain("build", go_script, "#!/bin/sh\ncat\n") do
      error = IO::Memory.new
      output_path = File.join(Tango::Workspace::Layout.cache_dir, "spec-build-output")

      result = Tango::Toolchain::Go.build_source("package main\nfunc main() {}\n", "spec_build.tn", output_path, error)

      result.status.should eq(0)
      result.diagnostics.should be_empty
      error.to_s.should contain("build-args:build -o #{output_path}")
      error.to_s.should contain("main.go")

      raced_error = IO::Memory.new
      raced = Tango::Toolchain::Go.build_source("package main\nfunc main() {}\n", "spec_build_race.tn", output_path, raced_error, race: true)

      raced.status.should eq(0)
      raced.diagnostics.should be_empty
      raced_error.to_s.should contain("build-args:build -race -o #{output_path}")
    end
  end

  it "returns a typed check when the selected Go executable disappears before execution" do
    go_script = version_script(<<-SH)
    if [ "$1" = "vet" ]; then
      rm "$0"
      exit 0
    fi
    exit 98
    SH

    fake_toolchain("disappearing", go_script, "#!/bin/sh\ncat\n") do
      result = Tango::Toolchain::Go.run_source("package main\nfunc main() {}\n", "disappearing.tn", IO::Memory.new, IO::Memory.new)

      result.status.should eq(1)
      result.diagnostics.first.code.should eq(Tango::Diagnostics::CHECK_GO)
      result.diagnostics.first.message.should contain("couldn't execute Go toolchain")
    end
  end

  it "returns a workspace check for incompatible module requirements" do
    fake_toolchain("module-conflict", version_script("exit 98"), "#!/bin/sh\ncat\n") do
      modules = [
        Tango::Target::Go::Runtime::ModuleRequirement.new("example.com/tool/v2", "v2.0.0"),
        Tango::Target::Go::Runtime::ModuleRequirement.new("example.com/tool/v2", "v2.1.0"),
      ]

      result = Tango::Toolchain::Go.run_source(
        "package main\nfunc main() {}\n",
        "module_conflict.tn",
        IO::Memory.new,
        IO::Memory.new,
        modules: modules
      )

      result.status.should eq(1)
      result.diagnostics.size.should eq(1)
      result.diagnostics.first.code.should eq(Tango::Diagnostics::CHECK_WORKSPACE)
      result.diagnostics.first.message.should contain("couldn't write generated Go source")
      result.diagnostics.first.message.should contain("incompatible requirements")
    end
  end
end
