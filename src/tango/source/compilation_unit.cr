module Tango
  module Source
    record RequireDirective, from : String, request : String, range : Range
    record RequireEdge, from : String, request : String, to : String, range : Range

    class CompilationUnit
      getter files : Array(File)
      getter entrypoint : File
      getter requires : Array(RequireDirective)
      getter edges : Array(RequireEdge)

      def initialize(
        @files : Array(File),
        @entrypoint : File,
        @requires : Array(RequireDirective) = [] of RequireDirective,
        @edges : Array(RequireEdge) = [] of RequireEdge,
      )
      end

      def self.single(file : File) : self
        new([file], file)
      end

      def file?(path : String) : File?
        @files.find { |file| file.path == path }
      end

      # Crystal receives every project file as a separate named source. Requires
      # have already been resolved by Tango, so blank only those directives while
      # retaining byte offsets and line endings for compiler locations.
      def semantic_code(file : File) : String
        relevant = @requires.select { |directive| directive.from == file.path }
        return file.code if relevant.empty?

        bytes = file.code.to_slice.dup
        relevant.each do |directive|
          range = directive.range
          range.start_offset.upto(range.end_offset - 1) do |offset|
            byte = bytes[offset]
            bytes[offset] = ' '.ord.to_u8 unless byte == '\n'.ord.to_u8 || byte == '\r'.ord.to_u8
          end
        end
        String.new(bytes)
      end
    end
  end
end
