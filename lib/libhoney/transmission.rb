require 'json'
require 'timeout'
require 'libhoney/response'
require 'libhoney/cleaner'

module Libhoney
  # @api private
  class TransmissionClient
    include Cleaner

    def initialize(max_batch_size: 50,
                   send_frequency: 100,
                   max_concurrent_batches: 10,
                   pending_work_capacity: 1000,
                   send_timeout: 10,
                   responses: nil,
                   block_on_send: false,
                   block_on_responses: false,
                   user_agent_addition: nil,
                   proxy_config: nil)

      @responses              = responses || SizedQueue.new(pending_work_capacity * 2)
      @block_on_send          = block_on_send
      @block_on_responses     = block_on_responses
      @max_batch_size         = max_batch_size
      # convert to seconds
      @send_frequency         = send_frequency.fdiv(1000)
      @max_concurrent_batches = max_concurrent_batches
      @pending_work_capacity  = pending_work_capacity
      @send_timeout           = send_timeout
      @user_agent             = build_user_agent(user_agent_addition).freeze
      @proxy_config           = proxy_config

      @send_queue   = Queue.new
      @threads      = []
      @lock         = Mutex.new
      # use a SizedQueue so the producer will block on adding to the batch_queue when @block_on_send is true
      @batch_queue  = SizedQueue.new(@pending_work_capacity)
      @batch_thread = nil
    end

    def add(event)
      return unless event_valid(event)

      begin
        @batch_queue.enq(event, !@block_on_send)
      rescue ThreadError
        # happens if the queue was full and block_on_send = false.
      end

      ensure_threads_running
    end

    def event_valid(event)
      invalid = []
      invalid.push('api host') if event.api_host.nil? || event.api_host.empty?
      invalid.push('write key') if event.writekey.nil? || event.writekey.empty?
      invalid.push('dataset') if event.dataset.nil? || event.dataset.empty?

      unless invalid.empty?
        e = StandardError.new("#{self.class.name}: nil or empty required fields (#{invalid.join(', ')})"\
          '. Will not attempt to send.')
        Response.new(error: e).tap do |error_response|
          error_response.metadata = event.metadata
          enqueue_response(error_response)
        end

        return false
      end

      true
    end

    def send_loop
      http_clients = build_http_clients

      # eat events until we run out
      loop do
        api_host, writekey, dataset, batch = @send_queue.pop
        break if batch.nil?

        before = Time.now

        begin
          http = http_clients[api_host]
          body = serialize_batch(batch)

          next if body.nil?

          headers = {
            'Content-Type' => 'application/json',
            'X-Honeycomb-Team' => writekey
          }

          response = http.post(
            "/1/batch/#{Addressable::URI.escape(dataset)}",
            body: body,
            headers: headers
          )
          process_response(response, before, batch)
        rescue Exception => e
          # catch a broader swath of exceptions than is usually good practice,
          # because this is effectively the top-level exception handler for the
          # sender threads, and we don't want those threads to die (leaving
          # nothing consuming the queue).
          begin
            batch.each do |event|
              # nil events in the batch should already have had an error
              # response enqueued in #serialize_batch
              next if event.nil?

              Response.new(error: e).tap do |error_response|
                error_response.metadata = event.metadata
                enqueue_response(error_response)
              end
            end
          rescue ThreadError
          end
        end
      end
    ensure
      http_clients.each do |_, http|
        begin
          http.close
        rescue StandardError
          nil
        end
      end
    end

    def close(drain)
      # if drain is false, clear the remaining unprocessed events from the queue
      unless drain
        @batch_queue.clear
        @send_queue.clear
      end

      @batch_queue.enq(nil)
      @batch_thread.join unless @batch_thread.nil?

      # send @threads.length number of nils so each thread will fall out of send_loop
      @threads.length.times { @send_queue << nil }

      @threads.each(&:join)
      @threads = []

      enqueue_response(nil)

      0
    end

    def batch_loop
      next_send_time = Time.now + @send_frequency
      batched_events = Hash.new do |h, key|
        h[key] = []
      end

      loop do
        begin
          Thread.handle_interrupt(Timeout::Error => :on_blocking) do
            while (event = Timeout.timeout(@send_frequency) { @batch_queue.pop })
              key = [event.api_host, event.writekey, event.dataset]
              batched_events[key] << event
            end
          end

          break
        rescue Exception
        ensure
          next_send_time = flush_batched_events(batched_events) if Time.now > next_send_time
        end
      end

      flush_batched_events(batched_events)
    end

    private

    ##
    # Enqueues a response to the responses queue suppressing ThreadError when
    # there is no space left on the queue and we are not blocking on response
    #
    def enqueue_response(response)
      @responses.enq(response, !@block_on_responses)
    rescue ThreadError
    end

    def process_response(http_response, before, batch)
      index = 0
      http_response.parse.each do |event|
        index += 1 while batch[index].nil? && index < batch.size
        break unless (batched_event = batch[index])

        Response.new(status_code: event['status']).tap do |response|
          response.duration = Time.now - before
          response.metadata = batched_event.metadata
          enqueue_response(response)
        end
      end
    end

    def serialize_batch(batch)
      payload = []
      batch.map! do |event|
        begin
          data = clean_data(event.data)

          e = {
            time: event.timestamp.iso8601(3),
            samplerate: event.sample_rate,
            data: data
          }

          payload << JSON.generate(e)

          event
        rescue StandardError => e
          Response.new(error: e).tap do |response|
            response.metadata = event.metadata
            enqueue_response(response)
          end

          nil
        end
      end

      return if payload.empty?

      "[#{payload.join(',')}]"
    end

    def build_user_agent(user_agent_addition)
      ua = "libhoney-rb/#{VERSION}"
      ua << " #{user_agent_addition}" if user_agent_addition
      ua
    end

    def ensure_threads_running
      @lock.synchronize do
        @batch_thread = Thread.new { batch_loop } unless @batch_thread && @batch_thread.alive?
        @threads.select!(&:alive?)
        @threads << Thread.new { send_loop } while @threads.length < @max_concurrent_batches
      end
    end

    def flush_batched_events(batched_events)
      batched_events.each do |(api_host, writekey, dataset), events|
        events.each_slice(@max_batch_size) do |batch|
          @send_queue << [api_host, writekey, dataset, batch]
        end
      end
      batched_events.clear

      Time.now + @send_frequency
    end

    def build_http_clients
      Hash.new do |h, api_host|
        client = HTTP.timeout(connect: @send_timeout, write: @send_timeout, read: @send_timeout)
                     .persistent(api_host)
                     .headers(
                       'User-Agent' => @user_agent,
                       'Content-Type' => 'application/json'
                     )

        client = client.via(*@proxy_config) unless @proxy_config.nil?
        h[api_host] = client
      end
    end
  end
end
