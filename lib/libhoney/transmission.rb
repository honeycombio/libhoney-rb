require 'libhoney/response'
require 'faraday'
require 'faraday_middleware'

module Libhoney
  # @api private
  class TransmissionClient
    def initialize(max_batch_size: 0,
                   send_frequency: 0,
                   max_concurrent_batches: 0,
                   pending_work_capacity: 0,
                   responses: 0,
                   block_on_send: 0,
                   block_on_responses: 0)

      @responses = responses
      @block_on_send = block_on_send
      @block_on_responses = block_on_responses
      @max_batch_size = max_batch_size
      @send_frequency = send_frequency
      @max_concurrent_batches = max_concurrent_batches
      @pending_work_capacity = pending_work_capacity

      # use a SizedQueue so the producer will block on adding to the send_queue when @block_on_send is true
      @send_queue = SizedQueue.new(@pending_work_capacity)
      @threads = []
      @lock = Mutex.new
    end

    def add(event)
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

        conn = Faraday.new(:url => e.api_host) do |faraday|
          faraday.request  :json
          faraday.adapter  :net_http_persistent
        end

        resp = conn.post do |req|
          req.url '/1/events/' + e.dataset
          req.headers = {
            'User-Agent' => "libhoney-rb/#{VERSION}",
            'Content-Type' => 'application/json',
            'X-Honeycomb-Team' => e.writekey,
            'X-Honeycomb-SampleRate' => e.sample_rate.to_s,
            'X-Event-Time' => e.timestamp.iso8601
          }
          req.body = e.data
        end

        # TODO handle faraday errors

        after = Time.now

        response = Response.new(:duration => after - before,
                                :status_code => resp.status,
                                :metadata => e.metadata)
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
  end
end
