require 'libhoney'

class TransmissionClientTest < Minitest::Test
  def test_event_with_empty_required_fields_is_rejected
    mockBuilder = Minitest::Mock.new()
    mockBuilder.expect :writekey, nil
    mockBuilder.expect :dataset, nil
    mockBuilder.expect :sample_rate, nil
    mockBuilder.expect :api_host, nil
    mockBuilder.expect :metadata, nil
    event = Libhoney::Event.new(nil, mockBuilder)

    response_queue = SizedQueue.new(10)
    transmission = Libhoney::TransmissionClient.new(responses: response_queue)
    transmission.add(event)

    # check event added to repsonse queue
    assert_equal(1, response_queue.length)
    e = response_queue.pop
    assert(e != nil)
    assert(e.error != nil)
    assert_equal('Libhoney::TransmissionClient: nil or empty required fields (api host, write key, dataset). Will not attemot to send.', e.error.message)
  end

  def test_event_with_empty_required_fields_is_rejected
    mockBuilder = Minitest::Mock.new()
    mockBuilder.expect :writekey, ""
    mockBuilder.expect :dataset, ""
    mockBuilder.expect :sample_rate, ""
    mockBuilder.expect :api_host, ""
    mockBuilder.expect :metadata, nil
    event = Libhoney::Event.new(nil, mockBuilder)

    response_queue = SizedQueue.new(10)
    transmission = Libhoney::TransmissionClient.new(responses: response_queue)
    transmission.add(event)

    # check event added to repsonse queue
    assert_equal(1, response_queue.length)
    e = response_queue.pop
    assert(e != nil)
    assert(e.error != nil)
    assert_equal('Libhoney::TransmissionClient: nil or empty required fields (api host, write key, dataset). Will not attemot to send.', e.error.message)
  end
end