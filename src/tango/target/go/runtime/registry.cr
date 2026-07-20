module Tango
  module Target
    module Go
      module Runtime
        module Registry
          private def self.widening_checked_arithmetic(name : String, go_type : String, operator : String) : Snippet
            wide_type = go_type.starts_with?("u") ? "uint64" : "int64"
            Snippet.new(<<-GO, deps: ["tangoOverflow"])
              func #{name}(a, b #{go_type}) #{go_type} {
                r := #{wide_type}(a) #{operator} #{wide_type}(b)
                if r != #{wide_type}(#{go_type}(r)) {
                  tangoOverflow()
                }
                return #{go_type}(r)
              }
              GO
          end

          private def self.integer_floor_arithmetic(name : String, go_type : String, crystal_type : String, bits : Int32, signed : Bool, operation : String) : Snippet
            if operation == "Div"
              overflow = signed ? <<-GO : ""
                  if a == #{go_type}(-1 << #{bits - 1}) && b == -1 {
                    panic(&tangoArgumentError{message: "Overflow: #{crystal_type}::MIN / -1"})
                  }
                GO
              correction = signed ? <<-GO : ""
                  if a%b != 0 && (a < 0) != (b < 0) {
                    q--
                  }
                GO
              Snippet.new(<<-GO, deps: ["tangoDivByZero", "tangoArgumentError"])
                func #{name}(a, b #{go_type}) #{go_type} {
                  if b == 0 {
                    tangoDivByZero()
                  }
                #{overflow}
                  q := a / b
                #{correction}
                  return q
                }
                GO
            else
              overflow = signed ? <<-GO : ""
                  if a == #{go_type}(-1 << #{bits - 1}) && b == -1 {
                    return 0
                  }
                GO
              correction = signed ? <<-GO : ""
                  if m != 0 && (m < 0) != (b < 0) {
                    m += b
                  }
                GO
              Snippet.new(<<-GO, deps: ["tangoDivByZero"])
                func #{name}(a, b #{go_type}) #{go_type} {
                  if b == 0 {
                    tangoDivByZero()
                  }
                #{overflow}
                  m := a % b
                #{correction}
                  return m
                }
                GO
            end
          end

          private def self.integer_shift(name : String, go_type : String, bits : Int32, left : Bool) : Snippet
            forward = left ? "<<" : ">>"
            reverse = left ? ">>" : "<<"
            Snippet.new(<<-GO, deps: ["tangoInteger", "tangoOverflow"])
              func #{name}[C tangoInteger](value #{go_type}, count C) #{go_type} {
                if count < 0 {
                  opposite := -count
                  if opposite < 0 {
                    tangoOverflow()
                  }
                  if uint64(opposite) >= #{bits} {
                    return 0
                  }
                  return value #{reverse} uint64(opposite)
                }
                if uint64(count) >= #{bits} {
                  return 0
                }
                return value #{forward} uint64(count)
              }
              GO
          end

          private def self.checked_integer_conversion(name : String, source_type : String, target_type : String, source_signed : Bool, target_signed : Bool) : Snippet
            negative_guard = source_signed && !target_signed ? <<-GO : ""
                if value < 0 {
                  tangoOverflow()
                }
              GO
            target_guard = !source_signed && target_signed ? <<-GO : ""
                if result < 0 {
                  tangoOverflow()
                }
              GO
            Snippet.new(<<-GO, deps: ["tangoOverflow"])
              func #{name}(value #{source_type}) #{target_type} {
              #{negative_guard}
                result := #{target_type}(value)
              #{target_guard}
                if #{source_type}(result) != value {
                  tangoOverflow()
                }
                return result
              }
              GO
          end

          private def self.string_to_integer(name : String, go_type : String, crystal_type : String, bits : Int32, signed : Bool) : Snippet
            parser = signed ? "ParseInt" : "ParseUint"
            Snippet.new(<<-GO, deps: ["tangoIntegerToken", "tangoArgumentError"], imports: ["strconv"])
              func #{name}(source string, base int32, whitespace, underscore, prefix, strict, leadingZeroIsOctal bool) #{go_type} {
                token, actualBase, ok := tangoIntegerToken(source, base, whitespace, underscore, prefix, strict, leadingZeroIsOctal)
                if !ok {
                  panic(&tangoArgumentError{message: "Invalid #{crystal_type}: " + strconv.Quote(source)})
                }
                value, err := strconv.#{parser}(token, actualBase, #{bits})
                if err != nil {
                  panic(&tangoArgumentError{message: "Invalid #{crystal_type}: " + strconv.Quote(source)})
                }
                return #{go_type}(value)
              }
              GO
          end

          private def self.wrapping_arithmetic(name : String, go_type : String, operator : String) : Snippet
            Snippet.new(<<-GO)
              func #{name}(left, right #{go_type}) #{go_type} {
                return left #{operator} right
              }
              GO
          end

          # Builtin exception structs all implement the same runtime protocol;
          # only their source name and ancestry differ. Generate that method
          # family from one table instead of copying five Go methods per class.
          private def self.builtin_exception(helper : String, class_name : String, ancestors : Array(String)) : Snippet
            membership = ancestors.map { |ancestor| %(name == "#{ancestor}") }.join(" || ")
            Snippet.new(<<-GO, deps: ["tangoException"])
              type #{helper} struct { message string }

              func (e *#{helper}) tangoExceptionMarker() {}
              func (e *#{helper}) tangoMessage() string { return e.message }
              func (e *#{helper}) tangoClass() string { return "#{class_name}" }
              func (e *#{helper}) tangoIsA(name string) bool { return #{membership} }
              func (e *#{helper}) Error() string { return e.message + " (#{class_name})" }
              GO
          end

          # Every checked cell through 32 bits is the same widening/round-trip
          # algorithm. Generate the width × operation matrix from metadata;
          # only 64-bit operations live outside this table because they have no
          # wider native Go integer.
          WIDENING_CHECKED_ARITHMETIC = begin
            snippets = {} of String => Snippet
            types = {
              "I8"  => "int8",
              "U8"  => "uint8",
              "I16" => "int16",
              "U16" => "uint16",
              "I32" => "int32",
              "U32" => "uint32",
            }
            operations = {"Add" => "+", "Sub" => "-", "Mul" => "*"}
            types.each do |suffix, go_type|
              operations.each do |operation, operator|
                name = "tango#{operation}#{suffix}"
                snippets[name] = widening_checked_arithmetic(name, go_type, operator)
              end
            end
            snippets
          end

          FLOOR_ARITHMETIC = begin
            snippets = {} of String => Snippet
            types = {
              "I8"  => {"int8", "Int8", 8, true},
              "U8"  => {"uint8", "UInt8", 8, false},
              "I16" => {"int16", "Int16", 16, true},
              "U16" => {"uint16", "UInt16", 16, false},
              "I32" => {"int32", "Int32", 32, true},
              "U32" => {"uint32", "UInt32", 32, false},
              "I64" => {"int64", "Int64", 64, true},
              "U64" => {"uint64", "UInt64", 64, false},
            }
            types.each do |suffix, (go_type, crystal_type, bits, signed)|
              {"Div", "Mod"}.each do |operation|
                name = "tangoFloor#{operation}#{suffix}"
                snippets[name] = integer_floor_arithmetic(name, go_type, crystal_type, bits, signed, operation)
              end
            end
            snippets
          end

          BUILTIN_EXCEPTION_TYPES = begin
            snippets = {} of String => Snippet
            types = {
              "tangoExceptionValue"        => {"Exception", %w(Exception)},
              "tangoOverflowError"         => {"OverflowError", %w(OverflowError Exception)},
              "tangoDivisionByZeroError"   => {"DivisionByZeroError", %w(DivisionByZeroError Exception)},
              "tangoArgumentError"         => {"ArgumentError", %w(ArgumentError Exception)},
              "tangoChannelClosedError"    => {"Channel::ClosedError", %w(Channel::ClosedError Exception)},
              "tangoKeyError"              => {"KeyError", %w(KeyError Exception)},
              "tangoTypeCastError"         => {"TypeCastError", %w(TypeCastError Exception)},
              "tangoIndexError"            => {"IndexError", %w(IndexError Exception)},
              "tangoIOError"               => {"IO::Error", %w(IO::Error Exception)},
              "tangoFileError"             => {"File::Error", %w(File::Error IO::Error Exception)},
              "tangoFileNotFoundError"     => {"File::NotFoundError", %w(File::NotFoundError File::Error IO::Error Exception)},
              "tangoFileAccessDeniedError" => {"File::AccessDeniedError", %w(File::AccessDeniedError File::Error IO::Error Exception)},
            }
            types.each do |helper, (class_name, ancestors)|
              snippets[helper] = builtin_exception(helper, class_name, ancestors)
            end
            snippets
          end

          SNIPPETS = {
            "tangoFileRead" => Snippet.new(<<-GO, deps: ["tangoIOError", "tangoFileError", "tangoFileNotFoundError", "tangoFileAccessDeniedError"], imports: ["errors", "io/fs", "os"]),
              func tangoFileRead(path string) string {
                contents, err := os.ReadFile(path)
                if err != nil {
                  if errors.Is(err, fs.ErrNotExist) {
                    panic(&tangoFileNotFoundError{message: "Error opening file with mode 'r': '" + path + "': No such file or directory"})
                  }
                  if errors.Is(err, fs.ErrPermission) {
                    panic(&tangoFileAccessDeniedError{message: "Error opening file with mode 'r': '" + path + "': Permission denied"})
                  }
                  var pathError *fs.PathError
                  if errors.As(err, &pathError) && pathError.Op == "read" {
                    panic(&tangoIOError{message: err.Error()})
                  }
                  panic(&tangoFileError{message: err.Error()})
                }
                return string(contents)
              }
              GO
            "tangoFileEachLine" => Snippet.new(<<-GO, deps: ["tangoIOError", "tangoFileError", "tangoFileNotFoundError", "tangoFileAccessDeniedError"], imports: ["bufio", "errors", "io", "io/fs", "os"]),
              func tangoFileEachLine(path string, block func(string)) {
                file, err := os.Open(path)
                if err != nil {
                  if errors.Is(err, fs.ErrNotExist) {
                    panic(&tangoFileNotFoundError{message: "Error opening file with mode 'r': '" + path + "': No such file or directory"})
                  }
                  if errors.Is(err, fs.ErrPermission) {
                    panic(&tangoFileAccessDeniedError{message: "Error opening file with mode 'r': '" + path + "': Permission denied"})
                  }
                  panic(&tangoFileError{message: err.Error()})
                }
                defer file.Close()

                reader := bufio.NewReader(file)
                for {
                  line, readErr := reader.ReadString('\\n')
                  if readErr != nil && !errors.Is(readErr, io.EOF) {
                    panic(&tangoIOError{message: readErr.Error()})
                  }
                  if len(line) > 0 {
                    if line[len(line)-1] == '\\n' {
                      line = line[:len(line)-1]
                      if len(line) > 0 && line[len(line)-1] == '\\r' {
                        line = line[:len(line)-1]
                      }
                    }
                    block(line)
                  }
                  if readErr != nil {
                    return
                  }
                }
              }
              GO
            # Numeric sleep is expressed in seconds at the language boundary.
            # Int32 and Float64 prelude overloads share this generic helper.
            "tangoSleep" => Snippet.new(<<-GO, imports: ["time"]),
              func tangoSleep[T int32 | float64](seconds T) {
                time.Sleep(time.Duration(float64(seconds) * float64(time.Second)))
              }
              GO

            "tangoNil" => Snippet.new(<<-GO),
              type tangoNil struct{}
              GO
            "tangoException" => Snippet.new(<<-GO),
              type tangoException interface {
                error
                tangoExceptionMarker()
                tangoMessage() string
                tangoClass() string
                tangoIsA(string) bool
              }
              GO
            "tangoUncaughtException" => Snippet.new(<<-GO, deps: ["tangoException"], imports: ["fmt", "os", "runtime/debug"]),
              func tangoUncaughtException() {
                recovered := recover()
                if recovered == nil {
                  return
                }
                exception, ok := recovered.(tangoException)
                if !ok {
                  panic(recovered)
                }
                fmt.Fprintf(os.Stderr, "Unhandled exception: %s (%s)\\n", exception.tangoMessage(), exception.tangoClass())
                debug.PrintStack()
                os.Exit(1)
              }
              GO
            "tangoCastFail" => Snippet.new(<<-GO, deps: ["tangoTypeCastError"]),
              func tangoCastFail(message string) {
                panic(&tangoTypeCastError{message: message})
              }
              GO
            "tangoOverflow" => Snippet.new(<<-GO, deps: ["tangoOverflowError"]),
              func tangoOverflow() {
                panic(&tangoOverflowError{message: "Arithmetic overflow"})
              }
              GO
            "tangoDivByZero" => Snippet.new(<<-GO, deps: ["tangoDivisionByZeroError"]),
              func tangoDivByZero() {
                panic(&tangoDivisionByZeroError{message: "Division by 0"})
              }
              GO
            "tangoAddI64" => Snippet.new(<<-GO, deps: ["tangoOverflow"]),
              func tangoAddI64(a, b int64) int64 {
                c := a + b
                if (c < a) != (b < 0) {
                  tangoOverflow()
                }
                return c
              }
              GO
            "tangoAddU64" => Snippet.new(<<-GO, deps: ["tangoOverflow"]),
              func tangoAddU64(a, b uint64) uint64 {
                c := a + b
                if c < a {
                  tangoOverflow()
                }
                return c
              }
              GO
            "tangoSubI64" => Snippet.new(<<-GO, deps: ["tangoOverflow"]),
              func tangoSubI64(a, b int64) int64 {
                c := a - b
                if (c > a) != (b < 0) {
                  tangoOverflow()
                }
                return c
              }
              GO
            "tangoSubU64" => Snippet.new(<<-GO, deps: ["tangoOverflow"]),
              func tangoSubU64(a, b uint64) uint64 {
                if a < b {
                  tangoOverflow()
                }
                return a - b
              }
              GO
            "tangoMulI64" => Snippet.new(<<-GO, deps: ["tangoOverflow"]),
              func tangoMulI64(a, b int64) int64 {
                if a == 0 || b == 0 {
                  return 0
                }
                const minI64 = -1 << 63
                if (a == minI64 && b == -1) || (b == minI64 && a == -1) {
                  tangoOverflow()
                }
                c := a * b
                if c/b != a {
                  tangoOverflow()
                }
                return c
              }
              GO
            "tangoMulU64" => Snippet.new(<<-GO, deps: ["tangoOverflow"]),
              func tangoMulU64(a, b uint64) uint64 {
                const maxU64 = ^uint64(0)
                if b != 0 && a > maxU64/b {
                  tangoOverflow()
                }
                return a * b
              }
              GO
            # Float64 arithmetic behind func boundaries — all-literal
            # operands would be Go constants, and Go rejects constant
            # div-by-zero / overflow at compile time where Crystal gives
            # runtime IEEE Infinity/NaN.
            "tangoAddF64" => Snippet.new(<<-GO),
              func tangoAddF64(a, b float64) float64 {
                return a + b
              }
              GO
            "tangoSubF64" => Snippet.new(<<-GO),
              func tangoSubF64(a, b float64) float64 {
                return a - b
              }
              GO
            "tangoMulF64" => Snippet.new(<<-GO),
              func tangoMulF64(a, b float64) float64 {
                return a * b
              }
              GO
            "tangoDivF64" => Snippet.new(<<-GO),
              func tangoDivF64(a, b float64) float64 {
                return a / b
              }
              GO
            "tangoFloorDivF64" => Snippet.new(<<-GO, imports: ["math"]),
              func tangoFloorDivF64(a, b float64) float64 {
                return math.Floor(a / b)
              }
              GO
            # Crystal Float#modulo is literally a - b * floor(a / b), not
            # math.Mod. Besides divisor-sign behavior this matters for finite
            # values modulo Infinity and normalizes exact results to +0.0.
            "tangoFloorModF64" => Snippet.new(<<-GO, deps: ["tangoDivByZero"], imports: ["math"]),
              func tangoFloorModF64(a, b float64) float64 {
                if b == 0 {
                  tangoDivByZero()
                }
                return a - b*math.Floor(a/b)
              }
              GO
            "tangoRoundEvenF64" => Snippet.new(<<-GO, imports: ["math"]),
              func tangoRoundEvenF64(value float64) float64 {
                return math.RoundToEven(value)
              }
              GO
            "tangoStringCompare" => Snippet.new(<<-GO, imports: ["strings"]),
              func tangoStringCompare(left, right string) int32 {
                return int32(strings.Compare(left, right))
              }
              GO
            # Crystal-style Float64 rendering. Go's %v prints `15`,
            # `1e+15`, `1e-05` where Crystal prints `15.0`, `1.0e+15`,
            # `1.0e-5`. Both sides use shortest-round-trip digits; only the
            # DRESSING differs: Crystal is fixed-notation iff the decimal
            # point lands in (-4, 15], always keeps a fractional digit, and
            # never zero-pads the exponent.
            "tangoFloatStr" => Snippet.new(<<-GO, imports: ["math", "strconv"]),
              func tangoFloatStr(f float64) string {
                if math.IsNaN(f) {
                  return "NaN"
                }
                if math.IsInf(f, 1) {
                  return "Infinity"
                }
                if math.IsInf(f, -1) {
                  return "-Infinity"
                }
                s := strconv.FormatFloat(f, 'e', -1, 64)
                sign := ""
                if s[0] == '-' {
                  sign = "-"
                  s = s[1:]
                }
                ei := 1
                for s[ei] != 'e' {
                  ei++
                }
                digits := s[:1]
                if ei > 2 {
                  digits += s[2:ei]
                }
                exp, _ := strconv.Atoi(s[ei+1:])
                point := exp + 1
                if point > 15 || point <= -4 {
                  frac := digits[1:]
                  if frac == "" {
                    frac = "0"
                  }
                  es := strconv.Itoa(exp)
                  if exp >= 0 {
                    es = "+" + es
                  }
                  return sign + digits[:1] + "." + frac + "e" + es
                }
                if point <= 0 {
                  zeros := ""
                  for i := 0; i < -point; i++ {
                    zeros += "0"
                  }
                  return sign + "0." + zeros + digits
                }
                for len(digits) < point {
                  digits += "0"
                }
                if len(digits) == point {
                  return sign + digits + ".0"
                }
                return sign + digits[:point] + "." + digits[point:]
              }
              GO
            "tangoPutsF64" => Snippet.new(<<-GO, deps: ["tangoFloatStr"], imports: ["fmt"]),
              func tangoPutsF64(f float64) {
                fmt.Println(tangoFloatStr(f))
              }
              GO
            "tangoChanRecv" => Snippet.new(<<-GO, deps: ["tangoChannelClosedError"]),
              func tangoChanRecv[T any](ch chan T) T {
                v, ok := <-ch
                if !ok {
                  panic(&tangoChannelClosedError{message: "Channel is closed"})
                }
                return v
              }
              GO
            "tangoArrayNew" => Snippet.new(<<-GO),
              func tangoArrayNew[T any]() *[]T {
                s := []T{}
                return &s
              }
              GO
            "tangoArrayBuild" => Snippet.new(<<-GO),
              func tangoArrayBuild[T any](n int32) *[]T {
                s := make([]T, n)
                return &s
              }
              GO
            "tangoArrayPush" => Snippet.new(<<-GO),
              func tangoArrayPush[T any](a *[]T, v T) *[]T {
                *a = append(*a, v)
                return a
              }
              GO
            "tangoArraySet" => Snippet.new(<<-GO),
              func tangoArraySet[T any](a *[]T, i int32, v T) T {
                (*a)[i] = v
                return v
              }
              GO
            "tangoStringSplit" => Snippet.new(<<-GO, imports: ["strings"]),
              func tangoStringSplit(s string) *[]string {
                fields := strings.Fields(s)
                return &fields
              }
              GO
            "tangoStringSplitOn" => Snippet.new(<<-GO, imports: ["strings"]),
              func tangoStringSplitOn(s string, separator string) *[]string {
                fields := strings.Split(s, separator)
                return &fields
              }
              GO
            "tangoStringToF64" => Snippet.new(<<-GO, deps: ["tangoArgumentError"], imports: ["strconv"]),
              func tangoStringToF64(s string) float64 {
                value, err := strconv.ParseFloat(s, 64)
                if err != nil {
                  panic(&tangoArgumentError{message: "Invalid Float64: " + strconv.Quote(s)})
                }
                return value
              }
              GO
            "tangoStringSize" => Snippet.new(<<-GO, imports: ["unicode/utf8"]),
              func tangoStringSize(s string) int32 {
                return int32(utf8.RuneCountInString(s))
              }
              GO
            "tangoStringCharAt" => Snippet.new(<<-GO, deps: ["tangoIndexError"], imports: ["unicode/utf8"]),
              func tangoStringCharAt(s string, index int32) rune {
                if index < 0 {
                  index += int32(utf8.RuneCountInString(s))
                }
                if index < 0 {
                  panic(&tangoIndexError{message: "Index out of bounds"})
                }
                offset := int32(0)
                for _, char := range s {
                  if offset == index {
                    return char
                  }
                  offset++
                }
                panic(&tangoIndexError{message: "Index out of bounds"})
              }
              GO
            "tangoStringEachChar" => Snippet.new(<<-GO),
              func tangoStringEachChar(s string, block func(rune)) {
                for _, char := range s {
                  block(char)
                }
              }
              GO
            "tangoStringEachCharBreak" => Snippet.new(<<-GO),
              func tangoStringEachCharBreak(s string, block func(rune) bool) {
                for _, char := range s {
                  if block(char) {
                    return
                  }
                }
              }
              GO
            "tangoStringSplitEach" => Snippet.new(<<-GO, deps: ["tangoNil"], imports: ["strings"]),
              func tangoStringSplitEach(s string, separator string, block func(string)) tangoNil {
                for {
                  index := strings.Index(s, separator)
                  if index < 0 {
                    block(s)
                    return tangoNil{}
                  }
                  block(s[:index])
                  s = s[index+len(separator):]
                }
              }
              GO
            "tangoStringSplitEachBreak" => Snippet.new(<<-GO, deps: ["tangoNil"], imports: ["strings"]),
              func tangoStringSplitEachBreak(s string, separator string, block func(string) bool) tangoNil {
                for {
                  index := strings.Index(s, separator)
                  if index < 0 {
                    block(s)
                    return tangoNil{}
                  }
                  if block(s[:index]) {
                    return tangoNil{}
                  }
                  s = s[index+len(separator):]
                }
              }
              GO
            "tangoPutsChar" => Snippet.new(<<-GO, imports: ["fmt"]),
              func tangoPutsChar(char rune) {
                fmt.Println(string(char))
              }
              GO
            "tangoHash" => Snippet.new(<<-GO),
              type tangoHash[K comparable, V any] struct {
                keys []K
                m map[K]V
              }
              GO
            "tangoHashNew" => Snippet.new(<<-GO, deps: ["tangoHash"]),
              func tangoHashNew[K comparable, V any]() *tangoHash[K, V] {
                return &tangoHash[K, V]{m: map[K]V{}}
              }
              GO
            "tangoHashSet" => Snippet.new(<<-GO, deps: ["tangoHash"]),
              func tangoHashSet[K comparable, V any](h *tangoHash[K, V], k K, v V) V {
                if _, ok := h.m[k]; !ok {
                  h.keys = append(h.keys, k)
                }
                h.m[k] = v
                return v
              }
              GO
            "tangoHashGet" => Snippet.new(<<-GO, deps: ["tangoHash", "tangoKeyError"], imports: ["fmt"]),
              func tangoHashGet[K comparable, V any](h *tangoHash[K, V], k K) V {
                v, ok := h.m[k]
                if !ok {
                  panic(&tangoKeyError{message: "Missing hash key: " + fmt.Sprint(k)})
                }
                return v
              }
              GO
            "tangoHashFetch" => Snippet.new(<<-GO, deps: ["tangoHash"]),
              func tangoHashFetch[K comparable, V any](h *tangoHash[K, V], k K, fallback V) V {
                if v, ok := h.m[k]; ok {
                  return v
                }
                return fallback
              }
              GO
            "tangoHashHas" => Snippet.new(<<-GO, deps: ["tangoHash"]),
              func tangoHashHas[K comparable, V any](h *tangoHash[K, V], k K) bool {
                _, ok := h.m[k]
                return ok
              }
              GO
          }.merge(WIDENING_CHECKED_ARITHMETIC)
            .merge(FLOOR_ARITHMETIC)
            .merge(INTEGER_SHIFTS)
            .merge(INTEGER_CONVERSIONS)
            .merge(STRING_TO_INTEGER)
            .merge(WRAPPING_ARITHMETIC)
            .merge(INTEGER_POWER)
            .merge(INTEGER_NEGATE)
            .merge(INTEGER_TOKEN)
            .merge(FLOAT_SYSTEMS)
            .merge(BUILTIN_EXCEPTION_TYPES)

          def self.snippet(name : String) : Snippet
            SNIPPETS[name]
          end
        end
      end
    end
  end
end
