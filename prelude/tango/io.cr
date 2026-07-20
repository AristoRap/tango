macro tango_puts(type)
  @[Primitive(:tango_external)]
  @[Go("fmt.Println")]
  def puts(x : {{type}}) : Nil
  end
end

tango_puts Int32
tango_puts Int8
tango_puts UInt8
tango_puts Int16
tango_puts UInt16
tango_puts UInt32
tango_puts Int64
tango_puts UInt64
tango_puts String
tango_puts Bool

@[Primitive(:tango_external)]
@[Go("tangoPutsChar")]
def puts(x : Char) : Nil
end

# floats print Crystal-style (15.0, 1.0e+16, NaN), not Go-style
# (15, 1e+16) — the dotless name binds the tangoPutsF64 runtime helper,
# not a package function.
@[Primitive(:tango_external)]
@[Go("tangoPutsF64")]
def puts(x : Float64) : Nil
end
