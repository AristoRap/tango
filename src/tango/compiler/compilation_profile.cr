module Tango
  module Compiler
    # User-selected compiler policy. Profiles never change Tango semantics;
    # planning alone may use Release to select evidence-backed realizations.
    enum CompilationProfile
      Development
      Release
    end
  end
end
