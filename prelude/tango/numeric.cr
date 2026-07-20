# Crystal declares its primitive integer surface as generated type matrices.
# Tango supports eight widths and mirrors that organization once; neutral IR
# carries the resolved width and operation instead of multiplying node classes.
macro tango_integer_system(type, conversion, signed)
  struct {{type}}
    include Comparable({{type}})

    {% for op in %w(< <= > >= == != ===) %}
      @[Primitive(:binary)]
      def {{op.id}}(other : {{type}}) : Bool
      end
    {% end %}

    def <=>(other : {{type}}) : Int32
      self > other ? 1 : (self < other ? -1 : 0)
    end

    def + : {{type}}
      self
    end

    {% if signed %}
      @[Primitive(:checked_negate)]
      def - : {{type}}
      end
    {% end %}

    @[Primitive(:checked_add)]
    def +(other : {{type}}) : {{type}}
    end

    @[Primitive(:checked_sub)]
    def -(other : {{type}}) : {{type}}
    end

    @[Primitive(:checked_mul)]
    def *(other : {{type}}) : {{type}}
    end

    @[Primitive(:floor_div)]
    def //(other : {{type}}) : {{type}}
    end

    @[Primitive(:floor_mod)]
    def %(other : {{type}}) : {{type}}
    end

    {% for other_type in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64) %}
      def /(other : {{other_type.id}}) : Float64
        self.to_f64 / other.to_f64
      end
    {% end %}

    {% for count_type in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64) %}
      @[Primitive(:integer_power)]
      def **(exponent : {{count_type.id}}) : {{type}}
      end

      @[Primitive(:integer_power)]
      def &**(exponent : {{count_type.id}}) : {{type}}
      end
    {% end %}

    def **(exponent : Float64) : Float64
      self.to_f64 ** exponent
    end

    {% for op in %w(+ - *) %}
      def {{op.id}}(other : Float64) : Float64
        self.to_f64 {{op.id}} other
      end
    {% end %}

    def /(other : Float64) : Float64
      self.to_f64 / other
    end

    def //(other : Float64) : {{type}}
      (self.to_f64 // other).{{conversion.id}}
    end

    {% for op in %w(< <= > >= == != ===) %}
      def {{op.id}}(other : Float64) : Bool
        self.to_f64 {{op.id}} other
      end
    {% end %}

    {% for op in %w(&+ &- &*) %}
      @[Primitive(:wrapping_arithmetic)]
      def {{op.id}}(other : {{type}}) : {{type}}
      end
    {% end %}

    {% for op in %w(& | ^) %}
      @[Primitive(:bitwise)]
      def {{op.id}}(other : {{type}}) : {{type}}
      end
    {% end %}

    @[Primitive(:bitwise_not)]
    def ~ : {{type}}
    end

    {% for count_type in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64) %}
      {% for op in %w(<< >>) %}
        @[Primitive(:integer_shift)]
        def {{op.id}}(count : {{count_type.id}}) : {{type}}
        end
      {% end %}
    {% end %}

    {% for target, name in {
                             Int8   => :to_i8,
                             UInt8  => :to_u8,
                             Int16  => :to_i16,
                             UInt16 => :to_u16,
                             Int32  => :to_i32,
                             UInt32 => :to_u32,
                             Int64  => :to_i64,
                             UInt64 => :to_u64,
                           } %}
      @[Primitive(:checked_integer_convert)]
      def {{name.id}} : {{target}}
      end

      @[Primitive(:wrapping_integer_convert)]
      def {{name.id}}! : {{target}}
      end
    {% end %}

    def to_i : Int32
      self.to_i32
    end

    def to_i! : Int32
      self.to_i32!
    end

    def to_u : UInt32
      self.to_u32
    end

    def to_u! : UInt32
      self.to_u32!
    end

    @[Primitive(:numeric_convert)]
    def to_f : Float64
    end

    def to_f64 : Float64
      self.to_f
    end

    def to_f64! : Float64
      self.to_f
    end
  end
end

tango_integer_system Int8, to_i8, true
tango_integer_system UInt8, to_u8, false
tango_integer_system Int16, to_i16, true
tango_integer_system UInt16, to_u16, false
tango_integer_system Int32, to_i32, true
tango_integer_system UInt32, to_u32, false
tango_integer_system Int64, to_i64, true
tango_integer_system UInt64, to_u64, false

struct Int32
  def times(& : Int32 ->) : Nil
    i = 0
    while i < self
      yield i
      i = i + 1
    end
  end
end

struct Float64
  include Comparable(Float64)

  {% for op in %w(< > == != ===) %}
    @[Primitive(:binary)]
    def {{op.id}}(other : Float64) : Bool
    end
  {% end %}

  def <=>(other : Float64) : Int32?
    return nil if self != self
    return nil if other != other
    self > other ? 1 : (self < other ? -1 : 0)
  end

  def + : Float64
    self
  end

  @[Primitive(:float_add)]
  def +(other : Float64) : Float64
  end

  @[Primitive(:float_sub)]
  def -(other : Float64) : Float64
  end

  @[Primitive(:float_mul)]
  def *(other : Float64) : Float64
  end

  @[Primitive(:float_div)]
  def /(other : Float64) : Float64
  end

  {% for other_type in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64) %}
    {% for op in %w(+ - *) %}
      def {{op.id}}(other : {{other_type.id}}) : Float64
        self {{op.id}} other.to_f64
      end
    {% end %}

    def /(other : {{other_type.id}}) : Float64
      self / other.to_f64
    end

    def //(other : {{other_type.id}}) : Float64
      self // other.to_f64
    end

    def %(other : {{other_type.id}}) : Float64
      self % other.to_f64
    end

    {% for op in %w(< <= > >= == != ===) %}
      def {{op.id}}(other : {{other_type.id}}) : Bool
        self {{op.id}} other.to_f64
      end
    {% end %}
  {% end %}

  @[Primitive(:floor_div)]
  def //(other : Float64) : Float64
  end

  @[Primitive(:floor_mod)]
  def %(other : Float64) : Float64
  end

  @[Primitive(:float_intrinsic)]
  def - : Float64
  end

  @[Primitive(:float_intrinsic)]
  def abs : Float64
  end

  @[Primitive(:float_intrinsic)]
  def sign_bit : Int32
  end

  @[Primitive(:float_intrinsic)]
  def ceil : Float64
  end

  @[Primitive(:float_intrinsic)]
  def floor : Float64
  end

  @[Primitive(:float_intrinsic)]
  def trunc : Float64
  end

  # Crystal's default Float64 rounding mode is ties to even.
  @[Primitive(:float_intrinsic)]
  def round : Float64
  end

  @[Primitive(:float_intrinsic)]
  def round_even : Float64
  end

  @[Primitive(:float_intrinsic)]
  def round_away : Float64
  end

  @[Primitive(:float_intrinsic)]
  def next_float : Float64
  end

  @[Primitive(:float_intrinsic)]
  def prev_float : Float64
  end

  @[Primitive(:float_power)]
  def **(exponent : Float64) : Float64
  end

  @[Primitive(:float_power)]
  def **(exponent : Int32) : Float64
  end

  {% for exponent_type in %w(Int8 UInt8 Int16 UInt16 UInt32 Int64 UInt64) %}
    def **(exponent : {{exponent_type.id}}) : Float64
      self ** exponent.to_f64
    end
  {% end %}

  def nan? : Bool
    self != self
  end

  def infinite? : Int32?
    return nil if nan?
    return nil if self == 0.0
    return nil if self != 2.0 * self
    self > 0.0 ? 1 : -1
  end

  def finite? : Bool
    return false if nan?
    if infinite?
      false
    else
      true
    end
  end

  def abs2 : Float64
    self * self
  end

  def sign : Int32
    self < 0.0 ? -1 : (self == 0.0 ? 0 : 1)
  end

  def integer? : Bool
    self % 1.0 == 0.0
  end

  def modulo(other : Float64) : Float64
    self % other
  end

  def remainder(other : Float64) : Float64
    mod = self % other
    return 0.0 if mod == 0.0
    if self > 0.0
      return mod if other > 0.0
    end
    if self < 0.0
      return mod if other < 0.0
    end
    mod - other
  end

  {% for target, name in {
                           Int8   => :to_i8,
                           UInt8  => :to_u8,
                           Int16  => :to_i16,
                           UInt16 => :to_u16,
                           Int32  => :to_i32,
                           UInt32 => :to_u32,
                           Int64  => :to_i64,
                           UInt64 => :to_u64,
                         } %}
    @[Primitive(:checked_float_convert)]
    def {{name.id}} : {{target}}
    end
  {% end %}

  def to_i : Int32
    to_i32
  end

  def to_u : UInt32
    to_u32
  end

  def to_f : Float64
    self
  end

  def to_f64 : Float64
    self
  end

  def to_f64! : Float64
    self
  end
end

struct Char
  @[Primitive(:char_ord)]
  def ord : Int32
  end
end
