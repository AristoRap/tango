module Tango
  module Target
    module Go
      class FromLIR
        private class HandlerContext
          alias ExitShape = Tango::IR::LIR::AbruptExit::Shape

          getter signal : String
          getter tags = Hash(ExitShape, Int32).new
          getter targets = Hash(ExitShape, String?).new
          getter inner_loops = Set(String).new
          property payload : String?

          def initialize(@signal : String)
          end

          def tag_for(shape : ExitShape) : Int32
            @tags[shape]? || begin
              tag = @tags.size + 1
              @tags[shape] = tag
              tag
            end
          end
        end

        # Owns generated-name state and preserves the established spellings.
        private class EmissionNames
          @ok_counter = 0
          @temp_counter = 0

          def ok : String
            name = "__ok#{@ok_counter}"
            @ok_counter += 1
            name
          end

          def temp(label : String) : String
            @temp_counter += 1
            "__tango_#{label}_#{@temp_counter}"
          end
        end

        # A function boundary owns its return type and its active handler
        # stack. Closures enter a fresh boundary, so they cannot accidentally
        # signal a handler belonging to an enclosing invocation.
        private class FunctionContext
          getter return_type : Tango::IR::Type?
          @handlers = [] of HandlerContext

          def initialize(@return_type : Tango::IR::Type? = nil)
          end

          def current_handler : HandlerContext?
            @handlers.last?
          end

          def handler : HandlerContext
            @handlers.last
          end

          def within(return_type : Tango::IR::Type?, &)
            saved_return_type = @return_type
            saved_handlers = @handlers
            @return_type = return_type
            @handlers = [] of HandlerContext
            begin
              yield
            ensure
              @return_type = saved_return_type
              @handlers = saved_handlers
            end
          end

          def with_handler(handler : HandlerContext, &)
            @handlers << handler
            begin
              yield
            ensure
              @handlers.pop
            end
          end
        end
      end
    end
  end
end
