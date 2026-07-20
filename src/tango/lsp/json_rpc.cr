require "json"

module Tango
  module Lsp
    # LSP uses JSON-RPC messages framed with Content-Length headers over stdio.
    module JsonRpc
      MAX_MESSAGE_BYTES = 64 * 1024 * 1024

      def self.read_message(input : IO, log_io : IO = STDERR) : JSON::Any?
        loop do
          length = nil
          while line = input.gets("\r\n", chomp: true)
            break if line.empty?
            if line.starts_with?("Content-Length:")
              length = line.split(':', 2)[1].strip.to_i?
            end
          end
          return nil if length.nil?

          if length < 0 || length > MAX_MESSAGE_BYTES
            log(log_io, "dropping frame with out-of-range Content-Length: #{length}")
            return nil
          end

          body = Bytes.new(length)
          input.read_fully(body)

          begin
            return JSON.parse(String.new(body))
          rescue JSON::ParseException
            log(log_io, "dropping malformed frame: body is not valid JSON")
            next
          end
        end
      rescue IO::EOFError
        nil
      end

      def self.write_message(output : IO, payload) : Nil
        body = payload.to_json
        output << "Content-Length: " << body.bytesize << "\r\n\r\n" << body
        output.flush
      end

      def self.log(io : IO, message : String) : Nil
        io.puts("[tango lsp] #{message}")
      end
    end
  end
end
