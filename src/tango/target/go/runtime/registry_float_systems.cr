module Tango
  module Target
    module Go
      module Runtime
        module Registry
          private def self.checked_float_to_integer(name : String, go_type : String, minimum : String, maximum : String) : Snippet
            Snippet.new(<<-GO, deps: ["tangoOverflow"], imports: ["math"])
              func #{name}(value float64) #{go_type} {
                if math.IsNaN(value) || value < #{minimum} || value > #{maximum} {
                  tangoOverflow()
                }
                return #{go_type}(value)
              }
              GO
          end

          FLOAT_SYSTEMS = begin
            snippets = {
              "tangoNegateF64" => Snippet.new(<<-GO),
                func tangoNegateF64(value float64) float64 { return -value }
                GO
              "tangoAbsF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoAbsF64(value float64) float64 { return math.Abs(value) }
                GO
              "tangoSignBitF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoSignBitF64(value float64) int32 {
                  if math.Signbit(value) { return -1 }
                  return 1
                }
                GO
              "tangoCeilF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoCeilF64(value float64) float64 { return math.Ceil(value) }
                GO
              "tangoFloorF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoFloorF64(value float64) float64 { return math.Floor(value) }
                GO
              "tangoTruncF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoTruncF64(value float64) float64 { return math.Trunc(value) }
                GO
              "tangoRoundAwayF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoRoundAwayF64(value float64) float64 { return math.Round(value) }
                GO
              "tangoNextF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoNextF64(value float64) float64 { return math.Nextafter(value, math.Inf(1)) }
                GO
              "tangoPreviousF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoPreviousF64(value float64) float64 { return math.Nextafter(value, math.Inf(-1)) }
                GO
              "tangoPowF64" => Snippet.new(<<-GO, imports: ["math"]),
                func tangoPowF64(base, exponent float64) float64 { return math.Pow(base, exponent) }
                GO
              "tangoPowIntegerF64" => Snippet.new(<<-GO),
                func tangoPowIntegerF64(base float64, exponent int32) float64 {
                  power := int64(exponent)
                  if power < 0 {
                    base = 1.0 / base
                    power = -power
                  }
                  result := 1.0
                  for power > 0 {
                    if power&1 != 0 { result *= base }
                    power >>= 1
                    if power > 0 { base *= base }
                  }
                  return result
                }
                GO
            } of String => Snippet

            targets = {
              "I8"  => {"int8", "-128.0", "127.0"},
              "U8"  => {"uint8", "0.0", "255.0"},
              "I16" => {"int16", "-32768.0", "32767.0"},
              "U16" => {"uint16", "0.0", "65535.0"},
              "I32" => {"int32", "-2147483648.0", "2147483647.0"},
              "U32" => {"uint32", "0.0", "4294967295.0"},
              "I64" => {"int64", "-9223372036854775808.0", "9223372036854774784.0"},
              "U64" => {"uint64", "0.0", "18446744073709549568.0"},
            }
            targets.each do |suffix, (go_type, minimum, maximum)|
              name = "tangoConvertF64To#{suffix}"
              snippets[name] = checked_float_to_integer(name, go_type, minimum, maximum)
            end
            snippets
          end
        end
      end
    end
  end
end
