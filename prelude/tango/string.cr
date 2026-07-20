class String
  include Comparable(String)
  include Sized

  # Crystal rewrites interpolation syntax to this call. The plumbing name is
  # reserved here; executable interpolation is handled by compiler lowering.
  @[Primitive(:tango_interpolation)]
  @[TangoInternal]
  def self.interpolation(*args) : String
  end

  @[Primitive(:binary)]
  def +(other : String) : String
  end

  @[Primitive(:binary)]
  def ==(other : String) : Bool
  end

  @[Primitive(:binary)]
  def !=(other : String) : Bool
  end

  # Crystal's case-sensitive ordering is a byte-wise three-way comparison.
  @[Primitive(:string_compare)]
  def <=>(other : String) : Int32
  end

  # Every character-facing String operation uses Unicode code points.
  # Bytes remain a distinct, explicit future surface.
  @[Primitive(:tango_string_size)]
  def size : Int32
  end

  @[Primitive(:tango_string_char_at)]
  def [](index : Int32) : Char
  end

  @[Primitive(:tango_string_each_char)]
  def each_char(& : Char ->) : Nil
  end

  # Split on runs of whitespace, omitting empty fields.
  @[Primitive(:tango_string_split)]
  def split : Array(String)
  end

  # Split on an exact string separator, retaining empty fields as Crystal does.
  @[Primitive(:tango_string_split)]
  def split(separator : String) : Array(String)
  end

  # Parses a Float64 decimal. Invalid text raises ArgumentError.
  @[Primitive(:tango_string_to_f)]
  def to_f : Float64
  end

  # Crystal's integer parser family shares one option contract. The strict
  # leaves remain compiler operations; nil-returning forms compose by rescuing
  # the same ArgumentError, so parsing policy has one owner.
  macro tango_string_integer_parser(type, name)
    @[Primitive(:tango_string_to_integer)]
    @[TangoInternal]
    def {{("__tango_" + name.stringify).id}}(base : Int32, whitespace : Bool, underscore : Bool, prefix : Bool, strict : Bool, leading_zero_is_octal : Bool) : {{type}}
    end

    def {{name.id}}(base : Int32 = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : {{type}}
      self.{{("__tango_" + name.stringify).id}}(base, whitespace, underscore, prefix, strict, leading_zero_is_octal)
    end

    def {{(name.stringify + "?").id}}(base : Int32 = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : {{type}}?
      begin
        self.{{("__tango_" + name.stringify).id}}(base, whitespace, underscore, prefix, strict, leading_zero_is_octal)
      rescue ArgumentError
        nil
      end
    end
  end

  tango_string_integer_parser Int8, to_i8
  tango_string_integer_parser UInt8, to_u8
  tango_string_integer_parser Int16, to_i16
  tango_string_integer_parser UInt16, to_u16
  tango_string_integer_parser Int32, to_i32
  tango_string_integer_parser UInt32, to_u32
  tango_string_integer_parser Int64, to_i64
  tango_string_integer_parser UInt64, to_u64

  def to_i(base : Int32 = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int32
    to_i32(base, whitespace, underscore, prefix, strict, leading_zero_is_octal)
  end

  def to_i?(base : Int32 = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int32?
    to_i32?(base, whitespace, underscore, prefix, strict, leading_zero_is_octal)
  end

  @[Primitive(:tango_external)]
  @[Go("strings.ToUpper")]
  def upcase : String
  end

  @[Primitive(:tango_external)]
  @[Go("strings.ToLower")]
  def downcase : String
  end
end
