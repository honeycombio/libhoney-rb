module Libhoney
  ##
  # This is the event object that you can fill up with data.
  # The data itself is a ruby hash.
  class Event
    attr_accessor :writekey, :dataset, :sample_rate, :api_host
    attr_accessor :timestamp, :metadata

    attr_reader :data
    
    # @api private
    # @see Client#event
    # @see Builder#event
    def initialize(libhoney, builder, fields = {}, dyn_fields = {})
      @libhoney = libhoney

      @writekey = builder.writekey
      @dataset = builder.dataset
      @sample_rate = builder.sample_rate
      @api_host = builder.api_host
      @timestamp = Time.now
      @metadata = nil

      @data = { }
      fields.each { |k, v| self.add_field(k, v) }
      dyn_fields.each { |k, v| self.add_field(k, v.call) }
      
      self
    end

    # adds a group of field->values to this event.
    #
    # @param newdata [Hash<String=>any>] field->value mapping.
    # @return [self] this event.
    # @example using an object
    #   builder.event
    #     .add({
    #       :responseTime_ms => 100,
    #       :httpStatusCode => 200
    #     })
    def add(newdata)
      @data.merge!(newdata)
      self
    end

    # adds a single field->value mapping to this event.
    #
    # @param name [String]
    # @param val [any]
    # @return [self] this event.
    # @example
    #   builder.event
    #     .add_field("responseTime_ms", 100)
    #     .send
    def add_field(name, val)
      @data[name] = val
      self
    end

    # times the execution of a block and adds a field containing the duration in milliseconds
    #
    # @param name [String] the name of the field to add to the event
    # @return [self] this event.
    # @example
    #   event.with_timer "task_ms" do
    #     # something time consuming
    #   end
    def with_timer(name, &block)
        start = Time.now
        block.call
        duration = Time.now - start
        # report in ms
        self.add_field(name, duration * 1000)
        self
    end
    
    # sends this event to honeycomb
    #
    # @return [self] this event.
    def send
      # discard if sampling rate says so
      if @libhoney.should_drop(self.sample_rate)
        @libhoney.send_dropped_response(self, "event dropped due to sampling")
        return
      end

      self.send_presampled()
    end

    # sends a presampled event to honeycomb
    #
    # @return [self] this event.
    def send_presampled
      raise ArgumentError.new("No metrics added to event. Won't send empty event.")         if self.data.length == 0
      @libhoney.send_event(self)
      self
    end
  end
end
