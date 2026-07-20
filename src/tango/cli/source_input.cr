module Tango
  module CLI
    # One command-line source entry. Materialization delegates canonical file
    # identity to the shared source model before graph loading.
    module SourceInput
      record Entry,
        filename : String,
        code : String,
        stable_path : Bool do
        def stable_path? : Bool
          @stable_path
        end

        def to_source : Tango::Source::File
          Tango::Source::File.canonical(@filename, @code, @stable_path)
        end
      end

      def self.read(path : String?, input : IO) : Entry
        case path
        when nil, "-"
          Entry.new("stdin.tn", input.gets_to_end, false)
        else
          Entry.new(path, File.read(path), true)
        end
      end
    end
  end
end
