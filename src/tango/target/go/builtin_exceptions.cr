module Tango
  module Target
    module Go
      # The builtin (compiler-provided) exceptions, mapping the Crystal class
      # name a `raise`/rescue refers to to the Go runtime helper that spells it.
      # This is the join between two independent enumerations: the frontend's
      # legality gate (`ToNIR#builtin_exception?`, Crystal names) and the runtime
      # registry (`Runtime::Registry::SNIPPETS`, Go helper names). The guardrail
      # spec pins all three against this one table so none can drift apart.
      BUILTIN_EXCEPTION_HELPERS = {
        "Exception"               => "tangoExceptionValue",
        "OverflowError"           => "tangoOverflowError",
        "DivisionByZeroError"     => "tangoDivisionByZeroError",
        "ArgumentError"           => "tangoArgumentError",
        "KeyError"                => "tangoKeyError",
        "TypeCastError"           => "tangoTypeCastError",
        "IndexError"              => "tangoIndexError",
        "Channel::ClosedError"    => "tangoChannelClosedError",
        "IO::Error"               => "tangoIOError",
        "File::Error"             => "tangoFileError",
        "File::NotFoundError"     => "tangoFileNotFoundError",
        "File::AccessDeniedError" => "tangoFileAccessDeniedError",
      }
    end
  end
end
