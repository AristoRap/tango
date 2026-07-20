module Tango
  module Compiler
    module Editor
      # Exact, protocol-neutral range query over semantic hint facts retained by
      # the editor index. An empty result is complete for the analyzed snapshot;
      # no syntax spelling is promoted into a type or parameter identity here.
      module InlayHints
        enum Completeness
          Exact
        end

        record Result,
          hints : Array(Index::InlayHint),
          completeness : Completeness = Completeness::Exact

        def self.in(snapshot : Snapshot, path : String, start_offset : Int32, end_offset : Int32) : Result
          hints = snapshot.editor_index.inlay_hints.select do |hint|
            anchor = hint.anchor
            anchor.path == path && anchor.start_offset < end_offset && anchor.end_offset >= start_offset
          end
          Result.new(hints)
        end
      end
    end
  end
end
