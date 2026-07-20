module Tango
  module Lsp
    # One immutable source-graph analysis request. Overlays are copied into the
    # forked child, so unsaved buffers follow exactly the same resolver and
    # expansion path as a normal compiler snapshot.
    record AnalysisRequest,
      revision : Int64,
      root_generation : Int64,
      root_uri : String,
      root_path : String,
      text : String,
      overlays : Hash(String, String),
      versions : Hash(String, Int32?),
      shadow : Bool = false do
      include JSON::Serializable
    end

    record AnalysisResult,
      request : AnalysisRequest,
      snapshot : Compiler::Snapshot,
      elapsed : Time::Span

    # Debounced, cancellable process isolation around Crystal's global semantic
    # compiler. A child returns only AnalysisCodec's immutable editor projection.
    class AnalysisWorker
      DEFAULT_DEBOUNCE       = 40.milliseconds
      DEFAULT_RECOVERY_LIMIT = 750.milliseconds
      CHILD_ENV              = "TANGO_EDITOR_ANALYSIS_WORKER"

      getter stale_results : Int32 = 0
      getter cancelled_results : Int32 = 0

      def initialize(
        @log : IO,
        @debounce : Time::Span = DEFAULT_DEBOUNCE,
        @recovery_limit : Time::Span = DEFAULT_RECOVERY_LIMIT,
        &@on_result : AnalysisResult -> Nil
      )
        @serials = Hash(String, Int64).new(0_i64)
        @active = {} of String => Process
        @busy = 0
      end

      def schedule(request : AnalysisRequest) : Nil
        key = request.root_uri
        @serials[key] += 1
        serial = @serials[key]
        cancel_active(key)
        @busy += 1
        spawn do
          sleep @debounce unless @debounce.zero?
          if serial != @serials[key]
            @stale_results += 1
            @busy -= 1
            next
          end

          run_background(request, key, serial)
        end
      end

      # Recovery is deliberately bounded. It uses an independent child so it
      # cannot mutate or cancel the authoritative background graph analysis.
      def recover(request : AnalysisRequest) : AnalysisResult?
        started = Time.instant
        process, reader = launch(request)
        result = Channel(Compiler::Snapshot?).new(1)
        spawn do
          result.send(read_snapshot(process, reader))
        end

        snapshot = select
        when value = result.receive
          value
        when timeout(@recovery_limit)
          terminate(process)
          nil
        end
        snapshot.try { |value| AnalysisResult.new(request, value, Time.instant - started) }
      end

      # Used only when the stdio stream closes (not on the normal request path),
      # so deterministic in-memory protocol specs can observe the last result.
      def drain(limit : Time::Span = 5.seconds) : Nil
        deadline = Time.instant + limit
        while @busy > 0 && Time.instant < deadline
          sleep 1.millisecond
        end
      end

      def stop : Nil
        @serials.keys.each { |key| @serials[key] += 1 }
        @active.keys.each { |key| cancel_active(key) }
      end

      def active?(root_uri : String) : Bool
        @active.has_key?(root_uri)
      end

      def self.child_process? : Bool
        ENV[CHILD_ENV]? == "1"
      end

      def self.run_child(input : IO = STDIN, output : IO = STDOUT) : Nil
        request = AnalysisRequest.from_json(input.gets_to_end)
        resolver = Frontend::SourceGraph.resolver(request.overlays)
        snapshot = Tango.pre_target_snapshot(
          request.text,
          filename: request.root_path,
          resolver: resolver
        )
        output << AnalysisCodec.dump(snapshot)
        output.flush
      rescue ex
        STDERR.puts "tango lsp analysis child failed: #{ex.message}"
      end

      private def run_background(request : AnalysisRequest, key : String, serial : Int64) : Nil
        started = Time.instant
        process, reader = launch(request)
        @active[key] = process
        snapshot = read_snapshot(process, reader)
        @active.delete(key) if @active[key]? == process
        if serial != @serials[key]
          @stale_results += 1
        elsif snapshot
          @on_result.call(AnalysisResult.new(request, snapshot, Time.instant - started))
        end
      ensure
        @busy -= 1
      end

      private def launch(request : AnalysisRequest) : {Process, IO}
        executable = Process.executable_path || raise "analysis worker has no executable path"
        process = Process.new(
          "env",
          ["#{CHILD_ENV}=1", executable],
          input: Process::Redirect::Pipe,
          output: Process::Redirect::Pipe,
          error: @log
        )
        process.input << request.to_json
        process.input.close
        {process, process.output}
      end

      private def read_snapshot(process : Process, reader : IO) : Compiler::Snapshot?
        payload = reader.gets_to_end
        status = process.wait
        return unless status.success? && !payload.empty?

        AnalysisCodec.load(payload)
      rescue ex
        @log.puts "tango lsp analysis worker failed: #{ex.message}"
        nil
      ensure
        reader.close rescue nil
      end

      private def cancel_active(key : String) : Nil
        if process = @active.delete(key)
          terminate(process)
          @cancelled_results += 1
        end
      end

      private def terminate(process : Process) : Nil
        process.terminate
      rescue
        nil
      end
    end
  end
end
