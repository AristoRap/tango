module Tango
  module Target
    module Go
      module Runtime
        record Snippet,
          code : String,
          deps : Array(String) = [] of String,
          imports : Array(String) = [] of String
      end
    end
  end
end
