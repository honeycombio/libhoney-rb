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
end
