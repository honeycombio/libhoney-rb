require 'libhoney/response'

module Libhoney
  # @api private
  class TransmissionClient
    def initialize(max_batch_size: 0,
                   send_frequency: 0,
                   max_concurrent_batches: 0,
                   pending_work_capacity: 0,
                   responses: 0,
                   block_on_send: 0,
                   block_on_responses: 0,
                   user_agent_addition: nil)

      @responses = responses
      @block_on_send = block_on_send
      @block_on_responses = block_on_responses
      @max_batch_size = max_batch_size
      @send_frequency = send_frequency
      @max_concurrent_batches = max_concurrent_batches
      @pending_work_capacity = pending_work_capacity

      @user_agent = build_user_agent(user_agent_addition).freeze

      # use a SizedQueue so the producer will block on adding to the send_queue when @block_on_send is true
      @send_queue = SizedQueue.new(@pending_work_capacity)
      @threads = []
      @lock = Mutex.new
    end

    def add(event)
      raise ArgumentError, "No APIHost for Honeycomb. Can't send to the Great Unknown." if event.api_host == ""
      raise ArgumentError, "No WriteKey specified. Can't send event." if event.writekey == ""
      raise ArgumentError, "No Dataset for Honeycomb. Can't send datasetless." if event.dataset == ""

      begin
        @send_queue.enq(event, !@block_on_send)
      rescue ThreadError
        # happens if the queue was full and block_on_send = false.
      end

      @lock.synchronize {
        return if @threads.length > 0
        while @threads.length < @max_concurrent_batches
          @threads << Thread.new { self.send_loop }
        end
      }
    end

    def send_loop
      # eat events until we run out
      loop {
        e = @send_queue.pop
        break if e == nil

        before = Time.now

        begin
          resp = HTTP.headers(
            'User-Agent' => @user_agent,
            'Content-Type' => 'application/json',
            'X-Honeycomb-Team' => e.writekey,
            'X-Honeycomb-SampleRate' => e.sample_rate,
            'X-Event-Time' => e.timestamp.iso8601
          ).post(URI.join(e.api_host, '/1/events/', URI.escape(e.dataset)), :json => e.data)

          response = Response.new(:status_code => resp.status)
        rescue Exception => error
          # catch a broader swath of exceptions than is usually good practice,
          # because this is effectively the top-level exception handler for the
          # sender threads, and we don't want those threads to die (leaving
          # nothing consuming the queue).
          response = Response.new(:error => error)
        ensure
          response.duration = Time.now - before
          response.metadata = e.metadata
        end

        begin
          @responses.enq(response, !@block_on_responses)
        rescue ThreadError
          # happens if the queue was full and block_on_send = false.
        end
      }
    end

    def close(drain)
      # if drain is false, clear the remaining unprocessed events from the queue
      @send_queue.clear if drain == false

      # send @threads.length number of nils so each thread will fall out of send_loop
      @threads.length.times { @send_queue << nil }

      @threads.each do |t|
        t.join
      end
      @threads = []

      @responses.enq(nil)

      0
    end

    private
    def build_user_agent(user_agent_addition)
      ua = "libhoney-rb/#{VERSION}"
      ua << " #{user_agent_addition}" if user_agent_addition
      ua
    end
  end
end
