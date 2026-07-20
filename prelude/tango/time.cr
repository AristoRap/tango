# Numeric seconds are the stable prelude contract until Tango grows a Time
# surface. Both overloads share one target runtime boundary.
@[Primitive(:tango_external)]
@[Go("tangoSleep")]
def sleep(seconds : Int32) : Nil
end

@[Primitive(:tango_external)]
@[Go("tangoSleep")]
def sleep(seconds : Float64) : Nil
end
