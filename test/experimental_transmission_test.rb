require 'test_helper'
require 'libhoney'
require 'libhoney/experimental_transmission'

class ExperimentalTransmissionClientTest < Minitest::Test
  def test_event_with_nil_required_fields_is_rejected
    mock_builder = Minitest::Mock.new
    mock_builder.expect :writekey, nil
    mock_builder.expect :dataset, nil
    mock_builder.expect :sample_rate, nil
    mock_builder.expect :api_host, nil
    mock_builder.expect :metadata, nil
    event = Libhoney::Event.new(nil, mock_builder)

    response_queue = SizedQueue.new(10)
    transmission = Libhoney::ExperimentalTransmissionClient.new(responses: response_queue)
    transmission.add(event)

    # check event added to response queue
    assert_equal(1, response_queue.length)
    e = response_queue.pop
    refute_nil(e)
    refute_nil(e.error)
    assert_equal(
      'Libhoney::ExperimentalTransmissionClient: nil or empty required fields (api_host, writekey, dataset).'\
      ' Will not attempt to send.',
      e.error.message
    )
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
    transmission = Libhoney::ExperimentalTransmissionClient.new(responses: response_queue)
    transmission.add(event)

    # check event added to response queue
    assert_equal(1, response_queue.length)
    e = response_queue.pop
    refute_nil(e)
    refute_nil(e.error)
    assert_equal(
      'Libhoney::ExperimentalTransmissionClient: nil or empty required fields (api_host, writekey, dataset).'\
      ' Will not attempt to send.',
      e.error.message
    )
  end

  def test_closing_does_not_error_when_no_threads_have_been_created
    transmission = Libhoney::ExperimentalTransmissionClient.new
    drain = true
    transmission.close(drain) # implicit assertion that this does not raise an error and fail the test
  end

  def test_closing_with_no_drain_does_not_error
    transmission = Libhoney::ExperimentalTransmissionClient.new
    drain = false
    transmission.close(drain) # implicit assertion that this does not raise an error and fail the test
  end

  def test_user_agent_annotation_for_experiment
    transmission = Libhoney::ExperimentalTransmissionClient.new

    assert_match "libhoney-rb/#{::Libhoney::VERSION} (exp-transmission) Ruby/#{RUBY_VERSION}",
                 transmission.__send__(:build_user_agent, nil)

    assert_match "libhoney-rb/#{::Libhoney::VERSION} (exp-transmission) awesome_sauce/42.2 Ruby/#{RUBY_VERSION}",
                 transmission.__send__(:build_user_agent, 'awesome_sauce/42.2')
  end
end
