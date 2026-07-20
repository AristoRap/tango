module Tango
  module IR
    # Tango's presentation categories for the scalar surface. Each category
    # names language behavior; targets implement that behavior in their own
    # vocabulary.
    enum ScalarPresentation
      Integer
      Float
      Bool
      String
      Nil
    end
  end
end
