require 'thread'
require 'time'
require 'json'
require 'http'

# define a few additions that proxy access through Client's builder.  makes Client much tighter.
class Class
  def builder_attr_accessor(*args)
    args.each do |arg|
      self.class_eval("def #{arg};@builder.#{arg};end")
      self.class_eval("def #{arg}=(val);@builder.#{arg}=val;end")
    end
  end
  def builder_attr_reader(*args)
    args.each do |arg|
      self.class_eval("def #{arg};@builder.#{arg};end")
    end
  end
  def builder_attr_writer(*args)
    args.each do |arg|
      self.class_eval("def #{arg}=(val);@builder.#{arg}=val;end")
    end
  end
end

module Libhoney
  ##
  # This is a library to allow you to send events to Honeycomb from within your
  # ruby application.
  #
  # Example:
  #   require 'libhoney'
  #   honey = Libhoney.new(writekey, dataset, url, sample_rate, num_workers)
  #   event = honey.event
  #   event.add({'pglatency' => 100})
  #   honey.send(event)
  #   <repeat creating and sending events until your program is finished>
  #   honey.close
  #
  # Arguments:
  # * *writekey* is the key to use the Honeycomb service
  # * *dataset* is the dataset to write into
  # * *sample_rate* is how many samples you want to keep.  IE:  1 means you want 1 out of 1 samples kept, or all of them.  10 means you want 1 out of 10 samples kept.  And so on.
  # * *url* is the url to connect to Honeycomb
  # * *num_workers* is the number of threads working on the queue of events you are generating
  #
  # Note that by default, the max queue size is 1000.  If the queue gets bigger than that, we start dropping events.
  #
  class Client
    # Instantiates libhoney and prepares it to send events to Honeycomb.
    #
    # @param writekey [String] the write key from your honeycomb team
    # @param dataset [String] the dataset you want
    # @param sample_rate [Fixnum] cause libhoney to send 1 out of sampleRate events.  overrides the libhoney instance's value.
    # @param api_host [String] the base url to send events to
    # @param block_on_send [Boolean] if more than pending_work_capacity events are written, block sending further events
    # @param block_on_responses [Boolean] if true, block if there is no thread reading from the response queue
    def initialize(writekey: '',
                   dataset: '',
                   sample_rate: 1,
                   api_host: 'https://api.honeycomb.io/',
                   block_on_send: false,
                   block_on_responses: false,
                   max_batch_size: 50,
                   send_frequency: 100,
                   max_concurrent_batches: 10,
                   pending_work_capacity: 1000)
      # check for insanity
      raise Exception.new('libhoney:  max_concurrent_batches must be greater than 0') if max_concurrent_batches < 1
      raise Exception.new('libhoney:  sample rate must be greater than 0') if sample_rate < 1

      raise Exception.new("libhoney:  Ruby versions < 2.2 are not supported") if !Gem::Dependency.new("ruby", "~> 2.2").match?("ruby", RUBY_VERSION)
      @builder = Builder.new(self, nil)
      @builder.writekey = writekey
      @builder.dataset = dataset
      @builder.sample_rate = sample_rate
      @builder.api_host = api_host

      @block_on_send = block_on_send
      @block_on_responses = block_on_responses
      @max_batch_size = max_batch_size
      @send_frequency = send_frequency
      @max_concurrent_batches = max_concurrent_batches
      @pending_work_capacity = pending_work_capacity
      @responses = SizedQueue.new(2 * @pending_work_capacity)
      @tx = nil
      @lock = Mutex.new

      self
    end

    builder_attr_accessor :writekey, :dataset, :sample_rate, :api_host

    attr_reader :block_on_send, :block_on_responses, :max_batch_size,
                :send_frequency, :max_concurrent_batches,
                :pending_work_capacity, :responses

    def event
      @builder.event
    end

    def builder(fields = {}, dyn_fields = {})
      @builder.builder(fields, dyn_fields)
    end

    ##
    # Nuke the queue and wait for inflight requests to complete before returning.
    # If you set drain=false, all queued requests will be dropped on the floor.
    def close(drain=true)
      return @tx.close(drain) if @tx
      0
    end

    # adds a group of field->values to the global Builder.
    #
    # @param data [Hash<String=>any>] field->value mapping.
    # @return [self] this Client instance
    # @example
    #   honey.add {
    #     :responseTime_ms => 100,
    #     :httpStatusCode => 200
    #   }
    def add(data)
      @builder.add(data)
      self
    end

    # adds a single field->value mapping to the global Builder.
    #
    # @param name [String] name of field to add.
    # @param val [any] value of field to add.
    # @return [self] this Client instance
    # @example
    #   honey.add_field("responseTime_ms", 100)
    def add_field(name, val)
      @builder.add_field(name, val)
      self
    end

    # adds a single field->dynamic value function to the global Builder.
    #
    # @param name [String] name of field to add.
    # @param fn [#call] function that will be called to generate the value whenever an event is created.
    # @return [self] this libhoney instance.
    # @example
    #   honey.addDynamicField("active_threads", Proc.new { Thread.list.select {|thread| thread.status == "run"}.count })
    def add_dynamic_field(name, fn)
      @builder.add_dynamic_field(name, fn)
      self
    end

    # creates and sends an event, including all global builder fields/dyn_fields, as well as anything in the optional data parameter.
    #
    # @param data [Hash<String=>any>] optional field->value mapping to add to the event sent.
    # @return [self] this libhoney instance.
    # @example empty sendNow
    #   honey.sendNow() # sends just the data that has been added via add/add_field/add_dynamic_field.
    # @example adding data at send-time
    #   honey.sendNow {
    #     additionalField: value
    #   }
    #/
    def send_now(data = {})
      @builder.send_now(data)
      self
    end

    ##
    # Enqueue an event to send.  Sampling happens here, and we will create
    # new threads to handle work as long as we haven't gone over max_concurrent_batches and
    # there are still events in the queue.
    #
    # @param event [Event] the event to send to honeycomb
    # @api private
    def send_event(event)
      @lock.synchronize {
        if !@tx
          @tx = TransmissionClient.new(:max_batch_size => @max_batch_size,
                                       :send_frequency => @send_frequency,
                                       :max_concurrent_batches => @max_concurrent_batches,
                                       :pending_work_capacity => @pending_work_capacity,
                                       :responses => @responses,
                                       :block_on_send => @block_on_send,
                                       :block_on_responses => @block_on_responses)
        end
      }

      @tx.add(event)
    end

    # @api private
    def send_dropped_response(event, msg)
      response = Response.new(:error => msg,
                              :metadata => event.metadata)
      begin
        @responses.enq(response, !@block_on_responses)
      rescue ThreadError
        # happens if the queue was full and block_on_responses = false.
      end
    end

    # @api private
    def should_drop(sample_rate)
      rand(1..sample_rate) != 1
    end

  end
end
