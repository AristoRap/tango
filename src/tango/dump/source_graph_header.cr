module Tango
  module Dump
    # Compile-time source inclusion is shared context for every phase dump. It
    # stays in a header rather than masquerading as a runtime NIR/LIR statement.
    module SourceGraphHeader
      def self.render(source : Source::CompilationUnit) : String
        String.build { |io| append(io, source) }
      end

      def self.append(io : IO, source : Source::CompilationUnit) : Nil
        io << "source_graph entry=" << source.entrypoint.path.inspect << '\n'
        io << "source_graph files=["
        source.files.each_with_index do |file, index|
          io << ", " unless index == 0
          io << file.path.inspect
        end
        io << "]\n"
        source.edges.each do |edge|
          io << "source_graph edge from=" << edge.from.inspect
          io << " request=" << edge.request.inspect
          io << " to=" << edge.to.inspect
          io << " @" << edge.range << '\n'
        end
      end
    end
  end
end
