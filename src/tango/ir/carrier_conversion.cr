module Tango
  module IR
    # Representation data shared by the planning decision and its self-contained
    # LIR materialization. Both phases own their surrounding node; this value
    # owns the carrier-to-carrier mapping shape so it is declared only once.
    class CarrierConversionMap
      record Variant,
        member : Type,
        source_tag : Int32,
        target_tag : Int32,
        source_label : String?,
        target_label : String?

      getter name : String
      getter source_name : String
      getter target_name : String
      getter variants : Array(Variant)

      def initialize(@name : String, @source_name : String, @target_name : String, @variants : Array(Variant))
      end
    end
  end
end
