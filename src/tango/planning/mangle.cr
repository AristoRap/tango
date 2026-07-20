module Tango
  module Planning
    # Signature-keyed function names for monomorphized defs.
    # A def name owns one function per concrete argument-type signature:
    # `factorial(Int32)` -> `factorial_Int32`, `identity(String)` ->
    # `identity_String`.
    module Mangle
      def self.func_name(name : String, arg_types : Array(IR::Type)) : String
        ([sanitize(name)] + arg_types.map { |type| sanitize(type.to_s) }).join("_")
      end

      # Injective type-name mangling:
      # alphanumerics pass through, `_` doubles, anything else escapes as
      # `u<hex>_`. Doubling `_` keeps the single-`_` segment join reversible,
      # so two distinct signatures can never collide into one name.
      def self.sanitize(type : String) : String
        String.build do |io|
          type.each_char do |char|
            if char.ascii_alphanumeric?
              io << char
            elsif char == '_'
              io << "__"
            else
              io << 'u' << char.ord.to_s(16) << '_'
            end
          end
        end
      end
    end
  end
end
