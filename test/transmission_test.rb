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
    assert(!e.nil?)
    assert(!e.error.nil?)
    assert_equal('Libhoney::TransmissionClient: nil or empty required fields (api host, write key, dataset). Will not attemot to send.', e.error.message)
  end

  def test_event_with_empty_required_fields_is_rejected
    mock_builder = Minitest::Mock.new
    mock_builder.expect :writekey, ""
    mock_builder.expect :dataset, ""
    mock_builder.expect :sample_rate, ""
    mock_builder.expect :api_host, ""
    mock_builder.expect :metadata, nil
    event = Libhoney::Event.new(nil, mock_builder)

    response_queue = SizedQueue.new(10)
    transmission = Libhoney::TransmissionClient.new(responses: response_queue)
    transmission.add(event)

    # check event added to repsonse queue
    assert_equal(1, response_queue.length)
    e = response_queue.pop
    assert(!e.nil?)
    assert(!e.error.nil?)
    assert_equal('Libhoney::TransmissionClient: nil or empty required fields (api host, write key, dataset). Will not attemot to send.', e.error.message)
  end
end
