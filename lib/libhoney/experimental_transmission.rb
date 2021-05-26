require 'libhoney/sized_queue_with_timeout'
require 'libhoney/transmission'

module Libhoney
  ##
  # An experimental variant of the standard {TransmissionClient} that uses
  # a custom implementation of a sized queue whose pop/push methods support
  # a timeout internally.
  #
  # @example Use this transmission with the Ruby Beeline
  #   Honeycomb.configure do |config|
  #     config.write_key = ENV["HONEYCOMB_WRITE_KEY"]
  #     config.dataset = ENV.fetch("HONEYCOMB_DATASET", "awesome_sauce")
  #     ...
  #   end
  #
  #   hnyclient = Honeycomb.libhoney
  #   hnyclient.change_transmission(
  #     Libhoney::ExperimentalTransmissionClient.new(**hnyclient.transmission_client_params)
  #   )
  #
  # @api private
  #
  class ExperimentalTransmissionClient < TransmissionClient
    def add(event)
      return unless event_valid(event)

      begin
        # if block_on_send is true, never timeout the wait to enqueue an event
        # otherwise, timeout the wait immediately and if the queue is full, we'll
        # have a ThreadError raised because we could not add to the queue.
        timeout = @block_on_send ? :never : 0
        @batch_queue.enq(event, timeout)
      rescue PushTimedOut
        # happens if the queue was full and block_on_send = false.
        warn "#{self.class.name}: batch queue full, dropping event." if %w[debug trace].include?(ENV['LOG_LEVEL'])
      end

      ensure_threads_running
    end

    def batch_loop
      next_send_time = Time.now + @send_frequency
      batched_events = Hash.new do |h, key|
        h[key] = []
      end

      loop do
        begin
          while (event = @batch_queue.pop(@send_frequency))
            key = [event.api_host, event.writekey, event.dataset]
            batched_events[key] << event
          end

          break
        rescue Libhoney::SizedQueueWithTimeout::PopTimedOut => e
          warn "#{self.class.name}: ⏱ " + e.message if %w[trace].include?(ENV['LOG_LEVEL'])
        rescue Exception => e # rubocop:disable Lint/RescueException
          warn "#{self.class.name}: 💥 " + e.message if %w[debug trace].include?(ENV['LOG_LEVEL'])
          warn e.backtrace.join("\n").to_s if ['trace'].include?(ENV['LOG_LEVEL'])
        ensure
          next_send_time = flush_batched_events(batched_events) if Time.now > next_send_time
        end
      end

      flush_batched_events(batched_events)
    end

    private

    def setup_batch_queue
      # override super()'s @batch_queue = SizedQueue.new(); use our SizedQueueWithTimeout:
      # + block on adding events to the batch_queue when queue is full and @block_on_send is true
      # + the queue knows how to limit size and how to time-out pushes and pops
      @batch_queue = SizedQueueWithTimeout.new(@pending_work_capacity)
      warn "⚠️🐆 #{self.class.name} in use! It may drop data, consume all your memory, or cause skin irritation."
    end
  end
end
