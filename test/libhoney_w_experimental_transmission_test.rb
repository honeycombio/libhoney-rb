require 'test_helper'
require 'json'
require 'stringio'
require 'minitest/mock'
require 'libhoney'
require 'libhoney/experimental_transmission'
require 'webmock/minitest'
require 'stub_honeycomb_server'
require 'spy'

class ExperimentalLibhoneyTest < Minitest::Test
  def setup
    @honey = Libhoney::Client.new(
      writekey: 'mywritekey',
      dataset: 'mydataset',
      send_frequency: 1,
      transmission: Libhoney::ExperimentalTransmissionClient
    )
  end

  def test_event
    assert_instance_of Libhoney::Event, @honey.event
  end

  def test_send
    # do 900 so that we fit under the queue size and don't drop events
    times_to_test = 900
    events = 0

    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset-send')
      .to_rack(StubHoneycombServer)

    event = @honey.event
    event.dataset = 'mydataset-send'
    event.add('argle' => 'bargle')
    event.add('invalid_characters' => "\x89")
    event.send

    assert_instance_of Libhoney::Event, event

    @honey.close
    @honey.responses.clear

    t = Thread.new do
      events += 1 while @honey.responses.pop
    end

    # ensure that the thread above is waiting for
    # an event to be pushed onto the queue
    test_waits_for { t.status == 'sleep' }

    (1..times_to_test).each do |i|
      event = @honey.event
      event.dataset = 'mydataset-send'
      event.add('test' => i)
      event.send
    end

    @honey.close

    t.join

    assert_equal times_to_test, events
  end

  def test_send_now
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset')
      .to_rack(StubHoneycombServer)

    @honey.send_now('argle' => 'bargle')

    @honey.close

    assert_requested :post, 'https://api.honeycomb.io/1/batch/mydataset', times: 1
  end

  def test_handle_interrupt
    stub_request(:post, 'https://api.honeycomb.io/1/batch/interrupt')
      .to_rack(StubHoneycombServer)

    Thread.handle_interrupt(Timeout::Error => :never) do
      (1..10).each do |i|
        event = @honey.event
        event.dataset = 'interrupt'
        event.add('test' => i)
        event.send
      end
    end

    sleep 1

    assert_requested :post, 'https://api.honeycomb.io/1/batch/interrupt', times: 1
  end

  def test_close
    times_to_test = 900

    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset-close')
      .to_rack(StubHoneycombServer)

    (1..times_to_test).each do |i|
      event = @honey.event
      event.dataset = 'mydataset-close'
      event.add('test' => i)
      event.send
    end
    thread_count = @honey.close

    assert_equal 0, thread_count
  end

  def test_response_metadata
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset-response_metadata')
      .to_rack(StubHoneycombServer)

    builder = @honey.builder
    builder.dataset = 'mydataset-response_metadata'
    builder.add_field('hi', 'bye')

    event = builder.event
    event.metadata = 42
    event.send

    resp = @honey.responses.pop
    assert_equal 42, resp.metadata

    event = builder.event
    event.metadata = 'string'
    event.send

    resp = @honey.responses.pop
    assert_equal 'string', resp.metadata
  end

  def check_and_drop(expected)
    lambda { |sample_rate|
      assert_equal(expected, sample_rate)
      true # always drop
    }
  end

  def does_not_send
    lambda { |_event|
      raise 'libhoney: unexpected send occured'
    }
  end

  def test_sampling
    builder = @honey.builder
    builder.dataset = 'mydataset-sampling'
    builder.add_field('hi', 'bye')

    @honey.stub(:send_event, does_not_send) do
      event = builder.event
      event.sample_rate = 5
      @honey.stub(:should_drop, check_and_drop(5)) do
        event.send
      end

      event = builder.event
      event.sample_rate = 1
      @honey.stub(:should_drop, check_and_drop(1)) do
        event.send
      end
    end
  end

  def test_error_handling
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset')
      .to_raise('the network is dark and full of errors')

    error_count = 20

    error_count.times do |n|
      event = @honey.event
      event.add_field 'attempt', n + 1
      event.send
    end

    error_count.times do
      response = @honey.responses.pop
      assert_kind_of(Exception, response.error)
      assert_equal(0, response.status_code)
    end

    assert @honey.responses.empty?

    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset')
      .to_rack(StubHoneycombServer)

    @honey.event
          .add_field('attempt', 'last')
          .send

    response = @honey.responses.pop
    assert_equal(202, response.status_code)

    @honey.close
  end

  def test_json_error_handling
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset')
      .to_rack(StubHoneycombServer)

    # simlulate an error generating json for an event
    json_generate = proc do |o|
      o[:data][:error] && raise(StandardError, 'no JSON for you')

      '{}'
    end

    JSON.stub :generate, json_generate do
      @honey.event.tap do |event|
        event.add_field(:error, true)
        event.metadata = 1
        event.send
      end
      @honey.event.tap do |event|
        event.add_field(:error, false)
        event.metadata = 2
        event.send
      end

      response = @honey.responses.pop
      assert_equal(1, response.metadata)
      assert_kind_of(Exception, response.error)
      assert_equal(0, response.status_code)

      response = @honey.responses.pop
      assert_equal(2, response.metadata)
      assert_equal(202, response.status_code)
    end
  end

  def test_dataset_quoting
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset%20send')
      .to_rack(StubHoneycombServer)

    event = @honey.event
    event.dataset = 'mydataset send'
    event.add('argle' => 'bargle')
    event.send

    @honey.close

    assert_requested :post, 'https://api.honeycomb.io/1/batch/mydataset%20send'
  end

  class ValueWithEventDuringTransmission
    def initialize(libhoney)
      @libhoney = libhoney
    end

    # to_s gets called by Libhoney::Cleaner on field values during
    # transmission, so if an instance of this class is assigned to a field on
    # an outer event, the inner event will be generated from within the
    # send_loop thread
    def to_s
      event.send
      'value'
    end

    def event
      event = @libhoney.event
      event.metadata = 'inner'
      event
    end
  end

  def test_event_during_transmission
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset').to_rack(StubHoneycombServer)

    event = @honey.event
    event.metadata = 'outer'
    event.add_field('field', ValueWithEventDuringTransmission.new(@honey))
    event.send

    # We can't rely on @honey.close to flush both events here. At first, only the outer event is in
    # the batch_queue. Once we call @honey.close, the outer event is flushed to the send_queue, and
    # the batch_loop exits. But then the inner event is triggered on the send_loop after we pop the
    # outer event off the send_queue. If we didn't prevent it, libhoney would proceed to push the
    # inner event to the batch_queue and start the batch_loop up all over again, along with more
    # send_loop threads. That effectively undoes the @honey.close and seems to lead to other
    # threading errors that are hard to grok: sometimes deadlocks, sometimes hanging indefinitely,
    # sometimes a different thread does the POST to Honeycomb but it's unstubbed on that thread...
    #
    # So instead of all that, wait a little bit for both events to get processed organically by the
    # existing batch_loop thread. It shouldn't take long.
    responses = []
    begin
      Timeout.timeout(1) do
        while (response = @honey.responses.pop)
          responses << response
        end
      end
    rescue Timeout::Error
      if responses.count < 2
        flunk "waited for libhoney to process 2 events, got #{responses.count} (try increasing timeout?)"
      elsif responses.count > 2
        flunk "expected only 2 events to be processed, got #{responses.count}: #{responses.inspect}"
      else
        @honey.close # should now be able to safely close, since we got through both of the events
      end
    end

    # the order of these responses changes before & after the associated fix,
    # so keeping this loose to run the test on both the old and new versions
    outer = responses.find { |response| response.metadata == 'outer' }
    inner = responses.find { |response| response.metadata == 'inner' }

    refute_nil outer, 'could not find response for outer event'
    refute_nil inner, 'could not find response for inner event'

    assert_nil outer.error, 'outer event should have succeeded'
    refute_nil inner.error, 'inner event should have been dropped'
  end

  class ValueWithInfiniteEventsDuringTransmission < ValueWithEventDuringTransmission
    def event
      event = super
      event.add_field('self', self) # self.to_s triggers yet another event when *this* event gets sent
      event
    end
  end

  def test_infinite_events_during_transmission
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset').to_rack(StubHoneycombServer)

    event = @honey.event
    event.metadata = 'outer'
    event.add_field('field', ValueWithInfiniteEventsDuringTransmission.new(@honey))
    event.send

    # Similar to test_event_during_transmission, we can't rely on @honey.close here. Furthermore,
    # the failure mode here results in an infinite loop anyway, so we just want to do this "wait for
    # a bit, then look at the results" pattern regardless.
    #
    # We still expect 2 responses, assuming the inner event that would have triggered the infinite
    # loop gets booted out as an error response.
    responses = []
    begin
      Timeout.timeout(1) do
        while (response = @honey.responses.pop)
          responses << response
        end
      end
    rescue Timeout::Error
      if responses.count > 2
        flunk "gave up after processing #{responses.count} events, probably reproduced an infinite loop bug"
      elsif responses.count < 2
        flunk "expected 2 events to be generated, got #{responses.count} (try increasing timeout?)"
      else
        @honey.close # should now be able to safely close, since we got both responses
      end
    end

    outer = responses.find { |response| response.metadata == 'outer' }
    inner = responses.find { |response| response.metadata == 'inner' }

    refute_nil outer, 'could not find response for outer event'
    refute_nil inner, 'could not find response for inner event'

    assert_nil outer.error, 'outer event should have succeeded'
    refute_nil inner.error, 'inner event should have been dropped'
  end
end

class ExperimentalLibhoneyResponseBlaster < Minitest::Test
  def setup
    @times_to_test = 2
    @honey = Libhoney::Client.new(
      writekey: 'mywritekey',
      dataset: 'mydataset',
      pending_work_capacity: 1,
      max_batch_size: 1,
      max_concurrent_batches: 1,
      send_frequency: 1,
      transmission: Libhoney::ExperimentalTransmissionClient
    )
  end

  ##
  # In this scenario we are testing inputs that would cause the response queue
  # to become full, but we are also subscribing to the responses and we test
  # that we get the correct number back
  #
  def test_response_queue_overload_subscriber
    events = 0

    t = Thread.new do
      events += 1 while @honey.responses.pop
    end

    # ensure that the thread above is waiting for
    # an event to be pushed onto the queue
    test_waits_for { t.status == 'sleep' }

    (1..@times_to_test).each do |i|
      event = @honey.event
      event.dataset = 'mydataset-send'
      event.add('test' => i)
      sleep 1
      event.send
    end
    @honey.close
    t.join

    assert_equal @times_to_test, events
  end

  ##
  # In this scenario we are testing inputs that would cause the response queue
  # to become full. Ensure that we can call close without issue
  #
  def test_response_queue_overload
    (1..@times_to_test).each do |i|
      event = @honey.event
      event.dataset = 'mydataset-send'
      event.add('test' => i)
      sleep 1
      event.send
    end

    @honey.close

    # we did it!
    assert true
  end
end
