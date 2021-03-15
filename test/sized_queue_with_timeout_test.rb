require 'test_helper'
require 'lockstep' # supplier of SyncThread
require 'libhoney/sized_queue_with_timeout'

class SizedQueueWithTimeoutTest < Minitest::Test
  def test_waiting_for_an_item
    q = Libhoney::SizedQueueWithTimeout.new
    consumer = Thread.new do
      q.pop
    end
    test_waits_for { consumer.status == 'sleep' }
    q.push 'hello'
    assert_equal('hello', consumer.value)
  end

  def test_trying_to_push_on_a_full_queue
    q = Libhoney::SizedQueueWithTimeout.new(3)
    consumer = Thread.new do
      q.pop
      sleep 1
    end
    q.push(1)
    q.push(2)
    q.push(3)
    q.push(4)
  end
end
