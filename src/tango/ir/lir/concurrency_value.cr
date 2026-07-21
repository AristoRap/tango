module Tango
  module IR
    module LIR
      # Target-neutral concurrency allocation and channel receive values.
      class MakeChan < Value
        getter element : IR::Type
        getter capacity : Value?

        def initialize(@element : IR::Type, @capacity : Value?)
        end
      end

      class MakeMutex < Value
        getter type : IR::Type

        def initialize(@type : IR::Type)
        end
      end

      abstract class ChannelReceiveValue < Value
        getter channel : Value
        getter element : IR::Type

        def initialize(@channel : Value, @element : IR::Type)
        end
      end

      class ChanReceive < ChannelReceiveValue
        def initialize(channel : Value, element : IR::Type)
          super(channel, element)
        end
      end

      class ChanReceiveMaybe < ChannelReceiveValue
        def initialize(channel : Value, element : IR::Type)
          super(channel, element)
        end
      end

      class ChanReceiveMaybeBox < ChannelReceiveValue
        getter union : IR::Type

        def initialize(channel : Value, element : IR::Type, @union : IR::Type)
          super(channel, element)
        end
      end

      class ChanReceiveState < ChannelReceiveValue
        getter result_type : IR::Type
        getter value_field : String
        getter open_field : String

        def initialize(channel : Value, element : IR::Type, @result_type : IR::Type, @value_field : String, @open_field : String)
          super(channel, element)
        end
      end
    end
  end
end
