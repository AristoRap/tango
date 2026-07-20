module Tango
  module Dump
    # Phase dumps share NIR identity, so facts and plans can expose the source
    # range of the node they describe without copying provenance into either
    # phase table. LIR has already committed ranges to line/column locations;
    # the overload keeps both spellings behind one rendering seam.
    module SourceLocations
      alias Index = Hash(NodeId, Source::Range)

      def self.index(program : IR::NIR::Program?) : Index
        ranges = Index.new
        return ranges unless program

        IR::NIR::Walk.children(program).each { |node| collect(node, ranges) }
        ranges
      end

      def self.append(io : IO, range : Source::Range?) : Nil
        range.try { |value| io << " @" << value }
      end

      def self.append(io : IO, loc : IR::LIR::SourceLoc?) : Nil
        loc.try { |value| io << " @" << value.file << ':' << value.line << ':' << value.column }
      end

      private def self.collect(node : IR::NIR::Stmt, ranges : Index) : Nil
        node.span.try { |span| ranges[node.id] = span }
        IR::NIR::Walk.children(node).each { |child| collect(child, ranges) }
      end
    end
  end
end
