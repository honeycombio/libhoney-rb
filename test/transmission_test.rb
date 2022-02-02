require 'test_helper'
require 'libhoney'

class TransmissionClientTest < Minitest::Test
  def test_event_with_nil_required_fields_is_rejected
    mock_builder = Minitest::Mock.new
    mock_builder.expect :writekey, nil
    mock_builder.expect :dataset, nil
    mock_builder.expect :sample_rate, nil
    mock_builder.expect :api_host, nil
    mock_builder.expect :metadata, nil
    event = Libhoney::Event.new(nil, mock_builder)

    response_queue = SizedQueue.new(10)
    transmission = Libhoney::TransmissionClient.new(responses: response_queue)
    transmission.add(event)

    # check event added to repsonse queue
    assert_equal(1, response_queue.length)
    e = response_queue.pop
    refute_nil(e)
    refute_nil(e.error)
    assert_equal('Libhoney::TransmissionClient: nil or empty required fields (api_host, writekey, dataset).'\
      ' Will not attempt to send.', e.error.message)
  end

  def test_event_with_empty_required_fields_is_rejected
    mock_builder = Minitest::Mock.new
    mock_builder.expect :writekey, ''
    mock_builder.expect :dataset, ''
    mock_builder.expect :sample_rate, ''
    mock_builder.expect :api_host, ''
    mock_builder.expect :metadata, nil
    event = Libhoney::Event.new(nil, mock_builder)

    response_queue = SizedQueue.new(10)
    transmission = Libhoney::TransmissionClient.new(responses: response_queue)
    transmission.add(event)

    # check event added to repsonse queue
    assert_equal(1, response_queue.length)
    e = response_queue.pop
    refute_nil(e)
    refute_nil(e.error)
    assert_equal('Libhoney::TransmissionClient: nil or empty required fields (api_host, writekey, dataset).'\
      ' Will not attempt to send.', e.error.message)
  end

  def test_closing_does_not_error_when_no_threads_have_been_created
    transmission = Libhoney::TransmissionClient.new
    drain = true
    transmission.close(drain) # implicit assertion that this does not raise an error and fail the test
  end

  def test_retry_half_closed_connections
    attempts = 0
    Excon.defaults[:mock] = true
    Excon.stub({ path: '/1/batch/sever_this_connection' }) do
      attempts += 1
      raise Excon::Error::Socket, EOFError.new('idle') if attempts <= 1

      { body: '[{ "status": 202 }]', status: 200 }
    end

    mock_builder = Minitest::Mock.new
    mock_builder.expect :writekey, 'write_key'
    mock_builder.expect :dataset, 'sever_this_connection'
    mock_builder.expect :sample_rate, 'sample_rate'
    mock_builder.expect :api_host, 'http://localhost:8080'
    event = Libhoney::Event.new(nil, mock_builder)

    response_queue = SizedQueue.new(10)
    transmission = Libhoney::TransmissionClient.new(responses: response_queue)
    transmission.add(event)
    sleep(0.5)

    assert_equal(1, response_queue.length)
    response = response_queue.pop
    refute_nil(response, 'There is a response for the event')
    assert_nil(response.error, 'No error on the response')
  ensure
    Excon.unstub({ path: '/1/batch/sever_this_connection' })
  end
end
