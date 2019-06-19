require 'timeout'
require 'libhoney/response'

module Libhoney
  # @api private
  class TransmissionClient
    def initialize(max_batch_size: 50,
                   send_frequency: 100,
                   max_concurrent_batches: 10,
                   pending_work_capacity: 1000,
                   send_timeout: 10,
                   responses: nil,
                   block_on_send: false,
                   block_on_responses: false,
                   user_agent_addition: nil)

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

      # use a SizedQueue so the producer will block on adding to the send_queue when @block_on_send is true
      @send_queue   = Queue.new
      @threads      = []
      @lock         = Mutex.new
      @batch_queue  = SizedQueue.new(@pending_work_capacity)
      @batch_thread = nil
    end

    def add(event)
      raise ArgumentError, "No APIHost for Honeycomb. Can't send to the Great Unknown." if event.api_host == ''
      raise ArgumentError, "No WriteKey specified. Can't send event."                   if event.writekey == ''
      raise ArgumentError, "No Dataset for Honeycomb. Can't send datasetless."          if event.dataset  == ''

      begin
        @batch_queue.enq(event, !@block_on_send)
      rescue ThreadError
        # happens if the queue was full and block_on_send = false.
      end

      ensure_threads_running
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
          url  = '/1/batch/' + Addressable::URI.escape(dataset)

          data = batch.map do |e|
            {
              time: e.timestamp.iso8601(3),
              samplerate: e.sample_rate,
              data: e.data
            }
          end

          resp = http.post(url,
                           json: data,
                           headers: {
                             'X-Honeycomb-Team' => writekey
                           })

          # "You must consume response before sending next request via persistent connection"
          # https://github.com/httprb/http/wiki/Persistent-Connections-%28keep-alive%29#note-using-persistent-requests-correctly
          resp.flush

          response = Response.new(status_code: resp.status)
        rescue Exception => error
          # catch a broader swath of exceptions than is usually good practice,
          # because this is effectively the top-level exception handler for the
          # sender threads, and we don't want those threads to die (leaving
          # nothing consuming the queue).
          response = Response.new(error: error)
        ensure
          if response
            response.duration = Time.now - before
            # response.metadata = event.metadata
          end
        end

        begin
          @responses.enq(response, !@block_on_responses) if response
        rescue ThreadError
          # happens if the queue was full and block_on_send = false.
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

      @batch_queue << nil
      @batch_thread.join

      # send @threads.length number of nils so each thread will fall out of send_loop
      @threads.length.times { @send_queue << nil }

      @threads.each(&:join)
      @threads = []

      @responses.enq(nil)

      0
    end

    def batch_loop
      next_send_time = Time.now + @send_frequency
      batched_events = Hash.new do |h, key|
        h[key] = []
      end

      loop do
        begin
          while (event = Timeout.timeout(@send_frequency) { @batch_queue.pop })
            key = [event.api_host, event.writekey, event.dataset]
            batched_events[key] << event
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
        h[api_host] = HTTP.timeout(connect: @send_timeout, write: @send_timeout, read: @send_timeout)
                          .persistent(api_host)
                          .headers(
                            'User-Agent' => @user_agent,
                            'Content-Type' => 'application/json'
                          )
      end
    end
  end
end
