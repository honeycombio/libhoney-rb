require 'json'
require 'stringio'
require 'minitest/autorun'
require 'minitest/mock'
require 'libhoney'
require 'webmock/minitest'
require 'sinatra/base'
require 'sinatra/json'

class HoneycombServer < Sinatra::Base
  set :json_encoder, :to_json

  before do
    @batch = JSON.parse(request.body.read.to_s)
  end

  post '/1/batch/:dataset' do
    json(@batch.map { { status: 202 } })
  end
end

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
                                 pending_work_capacity: 1500)

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
      .to_rack(HoneycombServer)

    builder = @honey.builder
    builder.send_now('argle' => 'bargle')

    @honey.close

    assert_requested :post, 'http://example.com/1/batch/dataset', times: 1
  end
end

class LibhoneyEventTest < Minitest::Test
  def setup
    params = { writekey: 'Xwritekey', dataset: 'Xdataset', api_host: 'Xurl' }
    @event = Libhoney::Client.new(params).event
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
      .to_rack(HoneycombServer)

    event = @honey.event
    event.dataset = 'mydataset-send'
    event.add('argle' => 'bargle')
    event.send

    assert_instance_of Libhoney::Event, event

    @honey.close
    @honey.responses.clear

    t = Thread.new do
      events += 1 while @honey.responses.pop
    end

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
      .to_rack(HoneycombServer)

    @honey.send_now('argle' => 'bargle')

    @honey.close

    assert_requested :post, 'https://api.honeycomb.io/1/batch/mydataset', times: 1
  end

  def test_close
    times_to_test = 900

    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset-close')
      .to_rack(HoneycombServer)

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
      .to_rack(HoneycombServer)

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
      raise Exception, 'libhoney: unexpected send occured'
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

    20.times do
      event = @honey.event
      event.add_field 'hi', 'bye'
      event.send
    end

    @honey.close

    while (response = @honey.responses.pop)
      assert_kind_of(Exception, response.error)
      assert_kind_of(HTTP::Response::Status, response.status_code)
    end

    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset')
      .to_rack(HoneycombServer)

    @honey.send_now('argle' => 'bargle')

    response = @honey.responses.pop
    assert_equal(202, response.status_code)

    @honey.close
  end

  def test_dataset_quoting
    stub_request(:post, 'https://api.honeycomb.io/1/batch/mydataset%20send')
      .to_rack(HoneycombServer)

    event = @honey.event
    event.dataset = 'mydataset send'
    event.add('argle' => 'bargle')
    event.send

    @honey.close

    assert_requested :post, 'https://api.honeycomb.io/1/batch/mydataset%20send'
  end
end

class LibhoneyUserAgentTest < Minitest::Test
  def setup
    stub_request(:post, 'https://api.honeycomb.io/1/batch/somedataset')
      .to_rack(HoneycombServer)
  end

  def test_default_user_agent
    honey = Libhoney::Client.new(writekey: 'mywritekey', dataset: 'somedataset')
    honey.send_now('ORLY' => 'YA RLY')
    honey.close

    assert_requested :post,
                     'https://api.honeycomb.io/1/batch/somedataset',
                     headers: { 'User-Agent': "libhoney-rb/#{::Libhoney::VERSION}" }
  end

  def test_user_agent_addition
    params = { writekey: 'mywritekey', dataset: 'somedataset', user_agent_addition: 'test/4.2' }
    honey = Libhoney::Client.new(params)
    honey.send_now('ORLY' => 'YA RLY')
    honey.close

    assert_requested :post,
                     'https://api.honeycomb.io/1/batch/somedataset',
                     headers: { 'User-Agent': %r{libhoney-rb/.* test/4.2} }
  end
end
