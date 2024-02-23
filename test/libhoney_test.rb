require 'test_helper'
require 'json'
require 'stringio'
require 'minitest/mock'
require 'libhoney'
require 'webmock/minitest'
require 'stub_honeycomb_server'
require 'spy'

class LibhoneyDefaultTest < Minitest::Test
  def setup
    # intercept warning emitted for missing writekey
    @old_stderr = $stderr
    $stderr = StringIO.new
  end

  def teardown
    $stderr = @old_stderr
  end

  def test_initialize_without_params
    honey = Libhoney::Client.new
    assert_nil honey.writekey
    assert_nil honey.dataset
    assert_match(/writekey/, $stderr.string, 'should log a warning due to missing writekey')
    assert_equal 1, honey.sample_rate
    assert_equal 'https://api.honeycomb.io/', honey.api_host
    assert_equal false, honey.block_on_send
    assert_equal false, honey.block_on_responses
    assert_equal 50, honey.max_batch_size
    assert_equal 100, honey.send_frequency
    assert_equal 10, honey.max_concurrent_batches
    assert_equal 1000, honey.pending_work_capacity
  end

  def test_initialize_with_params
    honey = Libhoney::Client.new(writekey: 'writekey', dataset: 'dataset', sample_rate: 4,
                                 api_host: 'http://example.com', block_on_send: true,
                                 block_on_responses: true, max_batch_size: 100,
                                 send_frequency: 150, max_concurrent_batches: 100,
                                 pending_work_capacity: 1500,
                                 proxy_config: 'http://username:password@proxy-hostname.local:8080')

    assert_equal 'writekey', honey.writekey
    assert_equal 'dataset', honey.dataset
    assert_equal 4, honey.sample_rate
    assert_equal 'http://example.com', honey.api_host
    assert_equal true, honey.block_on_send
    assert_equal true, honey.block_on_responses
    assert_equal 100, honey.max_batch_size
    assert_equal 150, honey.send_frequency
    assert_equal 100, honey.max_concurrent_batches
    assert_equal 1500, honey.pending_work_capacity
  end

  def test_initialize_with_classic_v3_ingestkey_and_dataset
    classic_v3_ingest_key = "hcaic_#{SecureRandom.alphanumeric(58)}"
    honey = Libhoney::Client.new(
      writekey: classic_v3_ingest_key,
      dataset: 'an dataset'
    )

    assert_equal classic_v3_ingest_key, honey.writekey
    assert_equal 'an dataset', honey.dataset
  end

  def test_initialize_with_non_classic_writekey_nil_dataset
    honey = Libhoney::Client.new(writekey: 'd68f9ed1e96432ac1a3380', dataset: nil)

    assert_match(/dataset/, $stderr.string, 'nil or empty dataset - sending data to \'unknown_dataset\'')
    assert_equal 'd68f9ed1e96432ac1a3380', honey.writekey
    assert_equal 'unknown_dataset', honey.dataset
  end

  def test_initialize_with_non_classic_writekey_empty_dataset
    honey = Libhoney::Client.new(writekey: 'd68f9ed1e96432ac1a3380', dataset: '')

    assert_match(/dataset/, $stderr.string, 'nil or empty dataset - sending data to \'unknown_dataset\'')
    assert_equal 'd68f9ed1e96432ac1a3380', honey.writekey
    assert_equal 'unknown_dataset', honey.dataset
  end

  def test_initialize_with_non_classic_writekey_and_dataset
    honey = Libhoney::Client.new(writekey: 'd68f9ed1e96432ac1a3380', dataset: 'dataset')

    assert_equal 'd68f9ed1e96432ac1a3380', honey.writekey
    assert_equal 'dataset', honey.dataset
  end

  def test_initialize_with_non_classic_writekey_and_dataset_with_whitespace
    honey = Libhoney::Client.new(writekey: 'd68f9ed1e96432ac1a3380', dataset: '  dataset  ')

    assert_match(
      /dataset/,
      $stderr.string,
      'dataset contained leading or trailing whitespace - sending data to \'dataset\''
    )
    assert_equal 'd68f9ed1e96432ac1a3380', honey.writekey
    assert_equal 'dataset', honey.dataset
  end
end

class LibhoneyKeyChecking < Minitest::Test
  def setup
    # set a bogus key to quiet warnings during initialization
    @honey = Libhoney::Client.new(writekey: "We don't care about this one.", dataset: 'whatevs')
  end

  def test_classic_key_32_chars
    assert @honey.classic_write_key? SecureRandom.alphanumeric(32)
  end

  def test_classic_key_v3_ingest
    assert @honey.classic_write_key? "hcaic_#{SecureRandom.alphanumeric(58)}"
  end

  def test_not_classic_key
    refute @honey.classic_write_key? SecureRandom.alphanumeric(22)
  end

  def test_not_classic_key_v3_ingest
    refute @honey.classic_write_key? "hcaik_#{SecureRandom.alphanumeric(58)}"
  end
end

class LibhoneyProxyTest < Minitest::Test
  def test_send_now_with_proxy
    stub_request(:post, 'http://example.com/1/batch/dataset')
      .with(headers: { 'Proxy-Authorization' => /^Basic / })
      .to_rack(StubHoneycombServer)

    honey = Libhoney::Client.new(writekey: 'writekey',
                                 dataset: 'dataset',
                                 sample_rate: 1,
                                 api_host: 'http://example.com',
                                 proxy_config: 'http://username:password@proxy-hostname.local:8080')
    builder = honey.builder
    builder.send_now('argle' => 'bargle')

    honey.close

    response = honey.responses.pop
    assert_nil(response.error)
    assert_equal(202, response.status_code)
  end
end

class LibhoneyProxyConfigArrayParsingTest < Minitest::Test
  def test_exception_raised_when_proxy_config_is_array
    exception = assert_raises RuntimeError do
      Libhoney::Client.new(
        writekey: 'writekey',
        dataset: 'dataset',
        proxy_config: ['proxy-hostname.local']
      )
    end
    assert_match(
      /proxy_config parameter requires a String value/, exception.message,
      'should state the required type for the proxy_config parameter'
    )
    assert_match(
      %r{set http/https_proxy}, exception.message,
      'should recommend using environment variables'
    )
    assert_match(
      /set proxy_config to a String/, exception.message,
      'should recommend using a string value for proxy_config'
    )
  end
end

class LibhoneyBuilderTest < Minitest::Test
  def setup
    @honey = Libhoney::Client.new(writekey: 'writekey',
                                  dataset: 'dataset',
                                  sample_rate: 1,
                                  api_host: 'http://example.com')
  end

  def teardown
    @honey.close(false)
  end

  def test_builder_inheritance
    @honey.add_field('argle', 'bargle')

    # create a new builder from the root builder
    builder = @honey.builder
    assert_equal 'writekey', builder.writekey
    assert_equal 'dataset', builder.dataset
    assert_equal 1, builder.sample_rate
    assert_equal 'http://example.com', builder.api_host

    # writekey, dataset, sample_rate, and api_host are all changeable on a builder
    builder.writekey = '1234'
    builder.dataset = '5678'
    builder.sample_rate = 4
    builder.api_host = 'http://builder.host'
    event = builder.event
    assert_equal '1234', event.writekey
    assert_equal '5678', builder.dataset
    assert_equal 4, builder.sample_rate
    assert_equal 'http://builder.host', builder.api_host

    # events from the sub-builder should include all root builder fields
    event = builder.event
    assert_equal 'bargle', event.data['argle']

    # but only up to the point where the sub builder was created
    @honey.add_field('argle2', 'bargle2')
    event = builder.event
    assert_nil event.data['argle2']

    # and fields added to the sub builder aren't accessible in the root builder
    builder.add_field('argle3', 'bargle3')
    event = @honey.event
    assert_nil event.data['argle3']
  end

  def test_dynamic_fields
    lam = -> { 42 }
    @honey.add_dynamic_field('lam', lam)

    proc = proc { 123 }
    @honey.add_dynamic_field('proc', proc)

    event = @honey.event
    assert_equal 42, event.data['lam']
    assert_equal 123, event.data['proc']
  end

  def test_send_now
    stub_request(:post, 'http://example.com/1/batch/dataset')
      .to_rack(StubHoneycombServer)

    builder = @honey.builder
    builder.send_now('argle' => 'bargle')

    @honey.close

    assert_requested :post, 'http://example.com/1/batch/dataset', times: 1
  end
end

class LibhoneyEventTest < Minitest::Test
  def setup
    params = { writekey: 'Xwritekey', dataset: 'Xdataset', api_host: 'Xurl' }
    @event = Libhoney::Client.new(**params).event
  end

  def test_overrides
    t = Time.now
    @event.writekey = 'Ywritekey'
    @event.dataset = 'Ydataset'
    @event.api_host = 'Yurl'
    @event.sample_rate = 10
    @event.timestamp = t
    assert_equal 'Ywritekey', @event.writekey
    assert_equal 'Ydataset', @event.dataset
    assert_equal 'Yurl', @event.api_host
    assert_equal 10, @event.sample_rate
    assert_equal t, @event.timestamp
  end

  def test_timestamp_is_time
    assert_instance_of Time, @event.timestamp
  end

  def test_add
    @event.add('foo' => 'bar')
    assert_equal 'bar', @event.data['foo']

    @event.add('map' => { 'one' => 1, 'two' => 'dos' })
    assert_equal ({ 'one' => 1, 'two' => 'dos' }), @event.data['map']
    assert_equal '{"foo":"bar","map":{"one":1,"two":"dos"}}', @event.data.to_json
  end
end

class LibhoneyTest < Minitest::Test
  def setup
    @honey = Libhoney::Client.new(writekey: 'mywritekey', dataset: 'mydataset')
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
    # simulate network errors between client and Honeycomb API
    network_error = StandardError.new('the network is dark and full of errors')
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset')
      .to_raise(network_error)

    error_count = 20

    error_count.times do |n|
      event = @honey.event
      event.add_field 'hi', 'bye'
      event.metadata = { network_error: n }
      event.send
    end

    @honey.close

    responses = @honey.responses.size.times.map { @honey.responses.pop }
    error_responses = responses.shift(error_count)

    assert_equal(
      error_count,
      error_responses.length,
      'We have as many responses as events we sent'
    )
    assert_equal(
      Array.new(error_count, network_error),
      error_responses.map(&:error),
      'The responses each have an exception about a network error'
    )
    assert_equal(
      Array.new(error_count) { |n| { network_error: n } },
      error_responses.map(&:metadata),
      'Each response has metadata from its associated event'
    )
    assert_equal(
      [nil],
      responses,
      'honey.close enqueues a nil to signal response handlers to end.'
    )

    # OK, the network is fixed now
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset')
      .to_rack(StubHoneycombServer)

    @honey.event.tap do |e|
      e.add_field('argle', 'bargle')
      e.metadata = { it_worked: true }
      e.send
    end

    response = @honey.responses.pop
    assert_equal(202, response.status_code)
    assert_equal({ it_worked: true }, response.metadata)

    @honey.close
  end

  def test_json_error_handling
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset')
      .to_rack(StubHoneycombServer)

    event_count = 5

    # Generate events with JSON.generate stubbed to raise an error if the event's
    # error field is true, otherwise a simple empty JSON object.
    json_error = StandardError.new('no JSON for you')
    JSON.stub :generate, ->(e) { e[:data][:error] ? raise(json_error) : '{}' } do
      event_count.times do |n|
        @honey.event.tap do |event|
          event.add_field(:error, n.odd?)
          event.metadata = n
          event.send
        end
      end

      responses = event_count.times.map { @honey.responses.pop }
      assert_equal(event_count, responses.size)

      errors = responses.select(&:error)
      assert_equal(
        event_count.div(2),
        errors.size,
        'Expect half (rounded down) of the number of events to have errored'
      )
      assert_equal(
        Array.new(event_count.div(2), json_error),
        errors.map(&:error),
        'Expect half (rounded down) of the events to have an error'
      )
    end
  end

  def test_error_response_handling
    stub_request(:post, 'https://api.honeycomb.io/1/batch/err-rate-limited')
      .to_rack(StubHoneycombServer)

    builder = @honey.builder
    builder.dataset = 'err-rate-limited'
    builder.add_field('chattiness', 'high')

    20.times do |n|
      event = builder.event
      event.metadata = n
      event.send
    end

    @honey.close

    errors = []
    while (response = @honey.responses.pop)
      errors << response
    end

    assert_equal 20, errors.length
    assert_equal (0..19).to_a, errors.map(&:metadata)
    assert_equal Array.new(20, RuntimeError.new('request dropped due to rate limiting')), errors.map(&:error)
    assert_equal Array.new(20, Libhoney::Response::Status.new(429)), errors.map(&:status_code)
  end

  def test_api_error_processing_coexists_with_json_error_processing
    stub_request(:post, 'https://api.honeycomb.io/1/batch/err-rate-limited')
      .to_rack(StubHoneycombServer)

    event_count = 4
    half_the_event_count = event_count.div(2)
    builder = @honey.builder
    builder.dataset = 'err-rate-limited'
    builder.add_field('chattiness', 'high')

    # Generate events with JSON.generate stubbed to raise an error if the event
    # is flagged to fail during serialization, otherwise serialize event with empty JSON object.
    json_error = StandardError.new('no JSON for you')
    JSON.stub :generate, ->(e) { e[:data][:fail_to_serialize] ? raise(json_error) : '{}' } do
      event_count.times do |n|
        builder.event.tap do |event|
          event.add_field(:fail_to_serialize, n.odd?)
          event.metadata = { event_number: n, fail_to_serialize: n.odd? }
          event.send
        end
      end

      @honey.close

      responses = []
      while (response = @honey.responses.pop)
        responses << response
      end
      assert_equal(event_count, responses.size, 'We have a response for each attempted event')

      serialization_error_responses = responses.select { |r| r.metadata[:fail_to_serialize] }
      assert_equal(
        half_the_event_count,
        serialization_error_responses.size,
        'Half of the error responses are for events that failed during serialization'
      )
      assert_equal(
        Array.new(half_the_event_count, json_error),
        serialization_error_responses.map(&:error),
        'A JSON error response was enqueued for each event flagged to fail during serialization'
      )

      remaining_responses = responses.reject { |r| r.metadata[:fail_to_serialize] }
      assert_equal(
        Array.new(responses.size - half_the_event_count, Libhoney::Response::Status.new(429)),
        remaining_responses.map(&:status_code),
        'The single error from the API was applied as the response for all serialized events sent in the batch'
      )
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
end

class LibhoneyTransmissionConfigTest < Minitest::Test
  def setup
    # intercept warning emitted for missing writekey
    @old_stderr = $stderr
    $stderr = StringIO.new
  end

  def teardown
    $stderr = @old_stderr
  end

  def test_no_config_given
    honey = Libhoney::Client.new
    assert_instance_of(
      Libhoney::NullTransmissionClient,
      honey.instance_variable_get(:@transmission),
      'without a key or dataset provided, the client should use the null/no-op transmission'
    )
  end

  def test_api_config_given
    honey = Libhoney::Client.new(writekey: 'writekey', dataset: 'dataset')
    assert_instance_of(
      Libhoney::TransmissionClient,
      honey.instance_variable_get(:@transmission),
      'with a key and dataset provided, the client should use the standard transmission'
    )
  end

  def test_parameters_passed_to_transmission
    honey = Libhoney::Client.new(
      writekey: 'writekey',
      dataset: 'dataset',
      user_agent_addition: 'test user agent',
      block_on_send: :test_block_on_send,
      block_on_responses: :test_block_on_responses,
      max_batch_size: 49,
      send_frequency: 99,
      max_concurrent_batches: 9,
      pending_work_capacity: 999,
      proxy_config: 'http://not.a.real.proxy'
    )
    test_transmission = honey.instance_variable_get(:@transmission)
    assert_instance_of Libhoney::TransmissionClient, test_transmission

    assert_match 'test user agent', test_transmission.instance_variable_get(:@user_agent)
    assert_equal :test_block_on_send, test_transmission.instance_variable_get(:@block_on_send)
    assert_equal :test_block_on_responses, test_transmission.instance_variable_get(:@block_on_responses)
    assert_equal 49, test_transmission.instance_variable_get(:@max_batch_size)
    assert_equal 0.099, test_transmission.instance_variable_get(:@send_frequency)
    assert_equal 9, test_transmission.instance_variable_get(:@max_concurrent_batches)
    assert_equal 999, test_transmission.instance_variable_get(:@pending_work_capacity)
    assert_equal 'http://not.a.real.proxy', test_transmission.instance_variable_get(:@proxy_config).to_s
  end

  def test_set_by_class
    honey = Libhoney::Client.new(
      writekey: 'writekey',
      dataset: 'dataset',
      transmission: Libhoney::ExperimentalTransmissionClient
    )
    assert_instance_of(
      Libhoney::ExperimentalTransmissionClient,
      honey.instance_variable_get(:@transmission),
      'when given a class for transmission, client should attempt to initialize that class'
    )
  end

  def test_set_to_configured_transmission_instance
    customized_transmission = Libhoney::TransmissionClient.new(user_agent_addition: 'custom')
    honey = Libhoney::Client.new(
      writekey: 'writekey',
      dataset: 'dataset',
      transmission: customized_transmission
    )
    assert_equal(
      customized_transmission,
      honey.instance_variable_get(:@transmission)
    )
  end

  def test_set_to_a_mocktransmission
    honey = Libhoney::Client.new(
      writekey: 'writekey',
      dataset: 'dataset',
      transmission: Libhoney::MockTransmissionClient
    )
    assert_instance_of(
      Libhoney::MockTransmissionClient,
      honey.instance_variable_get(:@transmission)
    )

    mock_transmission = Libhoney::MockTransmissionClient.new
    honey = Libhoney::Client.new(
      writekey: 'writekey',
      dataset: 'dataset',
      transmission: mock_transmission
    )
    assert_equal(
      mock_transmission,
      honey.instance_variable_get(:@transmission)
    )
  end

  class NotATransmission
    def initialize(**_); end
  end

  def test_set_by_a_bad_class
    honey = Libhoney::Client.new(
      writekey: 'writekey',
      dataset: 'dataset',
      transmission: NotATransmission
    )
    assert_instance_of(
      Libhoney::NullTransmissionClient,
      honey.instance_variable_get(:@transmission),
      'when given a class that does not behave like a transmission, client should use the no-op transmission'
    )
  end
end

class LibhoneyUserAgentTest < Minitest::Test
  def setup
    stub_request(:post, 'https://api.honeycomb.io/1/batch/somedataset')
      .to_rack(StubHoneycombServer)
  end

  def test_default_user_agent
    honey = Libhoney::Client.new(writekey: 'mywritekey', dataset: 'somedataset')
    honey.send_now('ORLY' => 'YA RLY')
    honey.close

    expected_user_agent =
      "libhoney-rb/#{::Libhoney::VERSION} Ruby/#{RUBY_VERSION} (#{RUBY_PLATFORM})"

    assert_requested :post,
                     'https://api.honeycomb.io/1/batch/somedataset',
                     headers: { 'User-Agent': expected_user_agent }
  end

  def test_user_agent_addition
    params = { writekey: 'mywritekey', dataset: 'somedataset', user_agent_addition: 'test/4.2' }
    honey = Libhoney::Client.new(**params)
    honey.send_now('ORLY' => 'YA RLY')
    honey.close

    assert_requested :post,
                     'https://api.honeycomb.io/1/batch/somedataset',
                     headers: { 'User-Agent': %r{libhoney-rb/.* test/4.2 Ruby/*.} }
  end
end

class LibhoneyResponseBlaster < Minitest::Test
  def setup
    @times_to_test = 2
    @honey = Libhoney::Client.new(
      writekey: 'mywritekey',
      dataset: 'mydataset',
      pending_work_capacity: 1,
      max_batch_size: 1,
      max_concurrent_batches: 1,
      send_frequency: 1
    )
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset-send')
      .to_rack(StubHoneycombServer)
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
      sleep 0.1
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
      sleep 0.1
      event.send
    end

    @honey.close

    # we did it!
    assert true
  end
end
