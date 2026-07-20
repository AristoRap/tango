module Tango
  module Target
    module Go
      module Runtime
        module Registry
          # Complete integer-system helper tables. Kept separate from the
          # general runtime registry so width matrices and parser policy have
          # one bounded owner.
          INTEGER_SHIFTS = begin
            snippets = {} of String => Snippet
            types = {
              "I8" => {"int8", 8}, "U8" => {"uint8", 8},
              "I16" => {"int16", 16}, "U16" => {"uint16", 16},
              "I32" => {"int32", 32}, "U32" => {"uint32", 32},
              "I64" => {"int64", 64}, "U64" => {"uint64", 64},
            }
            types.each do |suffix, (go_type, bits)|
              snippets["tangoShiftLeft#{suffix}"] = integer_shift("tangoShiftLeft#{suffix}", go_type, bits, true)
              snippets["tangoShiftRight#{suffix}"] = integer_shift("tangoShiftRight#{suffix}", go_type, bits, false)
            end
            snippets
          end

          private def self.integer_power(name : String, go_type : String, checked_mul : String? = nil) : Snippet
            multiply_result = checked_mul ? "#{checked_mul}(result, factor)" : "result * factor"
            multiply_factor = checked_mul ? "#{checked_mul}(factor, factor)" : "factor * factor"
            deps = ["tangoInteger", "tangoArgumentError"]
            deps << checked_mul if checked_mul
            Snippet.new(<<-GO, deps: deps)
              func #{name}[C tangoInteger](base #{go_type}, exponent C) #{go_type} {
                if exponent < 0 {
                  panic(&tangoArgumentError{message: "Cannot raise an integer to a negative integer power, use floats for that"})
                }
                result := #{go_type}(1)
                factor := base
                for exponent > 0 {
                  if exponent&1 != 0 { result = #{multiply_result} }
                  exponent >>= 1
                  if exponent > 0 { factor = #{multiply_factor} }
                }
                return result
              }
              GO
          end

          INTEGER_CONVERSIONS = begin
            snippets = {} of String => Snippet
            types = {
              "I8" => {"int8", true}, "U8" => {"uint8", false},
              "I16" => {"int16", true}, "U16" => {"uint16", false},
              "I32" => {"int32", true}, "U32" => {"uint32", false},
              "I64" => {"int64", true}, "U64" => {"uint64", false},
            }
            types.each do |source_suffix, (source_type, source_signed)|
              types.each do |target_suffix, (target_type, target_signed)|
                name = "tangoConvert#{source_suffix}To#{target_suffix}"
                snippets[name] = checked_integer_conversion(name, source_type, target_type, source_signed, target_signed)
                wrapping_name = "tangoWrappingConvert#{source_suffix}To#{target_suffix}"
                snippets[wrapping_name] = Snippet.new(<<-GO)
                  func #{wrapping_name}(value #{source_type}) #{target_type} {
                    return #{target_type}(value)
                  }
                  GO
              end
            end
            snippets
          end

          STRING_TO_INTEGER = begin
            snippets = {} of String => Snippet
            types = {
              "I8" => {"int8", "Int8", 8, true}, "U8" => {"uint8", "UInt8", 8, false},
              "I16" => {"int16", "Int16", 16, true}, "U16" => {"uint16", "UInt16", 16, false},
              "I32" => {"int32", "Int32", 32, true}, "U32" => {"uint32", "UInt32", 32, false},
              "I64" => {"int64", "Int64", 64, true}, "U64" => {"uint64", "UInt64", 64, false},
            }
            types.each do |suffix, (go_type, crystal_type, bits, signed)|
              name = "tangoStringTo#{suffix}"
              snippets[name] = string_to_integer(name, go_type, crystal_type, bits, signed)
            end
            snippets
          end

          WRAPPING_ARITHMETIC = begin
            snippets = {} of String => Snippet
            types = {
              "I8" => "int8", "U8" => "uint8", "I16" => "int16", "U16" => "uint16",
              "I32" => "int32", "U32" => "uint32", "I64" => "int64", "U64" => "uint64",
            }
            operations = {"WrappingAdd" => "+", "WrappingSub" => "-", "WrappingMul" => "*"}
            types.each do |suffix, go_type|
              operations.each do |operation, operator|
                name = "tango#{operation}#{suffix}"
                snippets[name] = wrapping_arithmetic(name, go_type, operator)
              end
            end
            snippets
          end

          INTEGER_POWER = begin
            snippets = {} of String => Snippet
            types = {
              "I8" => "int8", "U8" => "uint8", "I16" => "int16", "U16" => "uint16",
              "I32" => "int32", "U32" => "uint32", "I64" => "int64", "U64" => "uint64",
            }
            types.each do |suffix, go_type|
              checked = "tangoPow#{suffix}"
              snippets[checked] = integer_power(checked, go_type, "tangoMul#{suffix}")
              wrapping = "tangoWrappingPow#{suffix}"
              snippets[wrapping] = integer_power(wrapping, go_type)
            end
            snippets
          end

          INTEGER_NEGATE = begin
            snippets = {} of String => Snippet
            {"I8" => "int8", "I16" => "int16", "I32" => "int32", "I64" => "int64"}.each do |suffix, go_type|
              name = "tangoNegate#{suffix}"
              snippets[name] = Snippet.new(<<-GO, deps: ["tangoSub#{suffix}"])
                func #{name}(value #{go_type}) #{go_type} {
                  return tangoSub#{suffix}(0, value)
                }
                GO
            end
            snippets
          end

          INTEGER_TOKEN = {
            "tangoInteger" => Snippet.new(<<-GO),
              type tangoInteger interface {
                ~int8 | ~uint8 | ~int16 | ~uint16 | ~int32 | ~uint32 | ~int64 | ~uint64
              }
              GO
            "tangoIntegerToken" => Snippet.new(<<-GO, imports: ["strings"]),
              func tangoIntegerToken(source string, base int32, whitespace, underscore, prefix, strict, leadingZeroIsOctal bool) (string, int, bool) {
                text := source
                if whitespace {
                  asciiWhitespace := func(ch byte) bool {
                    return ch == ' ' || ch == '\\t' || ch == '\\n' || ch == '\\v' || ch == '\\f' || ch == '\\r'
                  }
                  start, end := 0, len(text)
                  for start < end && asciiWhitespace(text[start]) { start++ }
                  for end > start && asciiWhitespace(text[end-1]) { end-- }
                  text = text[start:end]
                }
                if text == "" || base < 0 || base == 1 || base > 36 { return "", 0, false }
                sign := ""
                if text[0] == '+' || text[0] == '-' {
                  sign, text = text[:1], text[1:]
                  if text == "" { return "", 0, false }
                }
                actualBase := int(base)
                if actualBase == 0 { actualBase = 10 }
                if len(text) >= 2 && text[0] == '0' && (prefix || base == 0) {
                  switch text[1] {
                  case 'b', 'B': actualBase, text = 2, text[2:]
                  case 'o', 'O': actualBase, text = 8, text[2:]
                  case 'x', 'X': actualBase, text = 16, text[2:]
                  }
                } else if leadingZeroIsOctal && base == 10 && len(text) > 1 && text[0] == '0' {
                  actualBase = 8
                }
                if text == "" { return "", 0, false }
                digit := func(ch byte) int {
                  switch {
                  case ch >= '0' && ch <= '9': return int(ch - '0')
                  case ch >= 'a' && ch <= 'z': return int(ch-'a') + 10
                  case ch >= 'A' && ch <= 'Z': return int(ch-'A') + 10
                  default: return -1
                  }
                }
                var cleaned strings.Builder
                cleaned.WriteString(sign)
                consumed := 0
                previousDigit := false
                for index := 0; index < len(text); index++ {
                  ch := text[index]
                  if ch == '_' {
                    nextDigit := index+1 < len(text) && digit(text[index+1]) >= 0 && digit(text[index+1]) < actualBase
                    if !underscore || !previousDigit || !nextDigit {
                      if strict { return "", 0, false }
                      break
                    }
                    previousDigit = false
                    consumed++
                    continue
                  }
                  value := digit(ch)
                  if value < 0 || value >= actualBase {
                    if strict { return "", 0, false }
                    break
                  }
                  cleaned.WriteByte(ch)
                  previousDigit = true
                  consumed++
                }
                if consumed == 0 || !previousDigit { return "", 0, false }
                return cleaned.String(), actualBase, true
              }
              GO
          }
        end
      end
    end
  end
end
