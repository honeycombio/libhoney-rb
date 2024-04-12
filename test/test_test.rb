require 'test_helper'
require 'libhoney'

# Tests for TestClient, which provides support for testing instrumented code.
class LibhoneyTestTest < Minitest::Test
  def test_test_client
    fakehoney = Libhoney::TestClient.new

    fakehoney.send_now('argle' => 'bargle')

    assert_equal 1, fakehoney.events.size

    event = fakehoney.events[0]
    assert_equal 'bargle', event.data['argle']
  end

  # We could imagine a pathological case where Array#push is monkey-patched to generate
  # libhoney events. This would probably break lots of other things, but since the
  # implementation of the MockTransmissionClient#add simply pushes the incoming event onto
  # an array, it may also generate an infinite loop unless we avoid sending the events
  # generated during transmission. So, it seems worth the minor effort.
  def test_events_during_transmission
    libhoney = Libhoney::TestClient.new

    count = 0
    push = lambda do |event|
      count += 1
      assert_equal 'outer', event.metadata, 'inner events should not be pushed'
      assert_equal 1, count, 'attempted to push multiple outer events'
      inner_event = libhoney.event
      inner_event.metadata = 'inner'
      inner_event.send
    end

    libhoney.events.stub(:push, push) do
      outer_event = libhoney.event
      outer_event.metadata = 'outer'
      outer_event.send
    end

    assert_equal 1, count, 'outer event did not get pushed'
  end
end
