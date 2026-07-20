require "./core"
require "./workspace"
require "./toolchain"
require "./frontend"
require "./compiler/driver"
require "./compiler/pipeline"

module Tango
  def self.compile(source : String, filename : String = "source.tn", profile : Compiler::CompilationProfile = Compiler::CompilationProfile::Development) : String
    Compiler::Pipeline.new.compile(source, filename, profile)
  end

  def self.snapshot(
    source : String,
    filename : String = "source.tn",
    resolver : Frontend::SourceGraph::Resolver = Frontend::SourceGraph::DISK_RESOLVER,
    stable_path : Bool = true,
    profile : Compiler::CompilationProfile = Compiler::CompilationProfile::Development,
  ) : Compiler::Snapshot
    Compiler::Pipeline.new.snapshot(source, filename, resolver, stable_path: stable_path, profile: profile)
  end

  def self.pre_target_snapshot(
    source : String,
    filename : String = "source.tn",
    resolver : Frontend::SourceGraph::Resolver = Frontend::SourceGraph::DISK_RESOLVER,
    stable_path : Bool = true,
    profile : Compiler::CompilationProfile = Compiler::CompilationProfile::Development,
  ) : Compiler::Snapshot
    Compiler::Pipeline.new.pre_target_snapshot(source, filename, resolver, stable_path: stable_path, profile: profile)
  end

  def self.editor_surface_snapshot(
    source : String,
    filename : String = "source.tn",
    resolver : Frontend::SourceGraph::Resolver = Frontend::SourceGraph::DISK_RESOLVER,
    stable_path : Bool = true,
  ) : Compiler::Snapshot
    Compiler::Pipeline.new.editor_surface_snapshot(source, filename, resolver, stable_path: stable_path)
  end
end
