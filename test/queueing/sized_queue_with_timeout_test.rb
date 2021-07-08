require 'test_helper'
require 'lockstep' # supplier of SyncThread
require 'libhoney/queueing/sized_queue_with_timeout'

class PopFromSizedQueueWithTimeoutTest < Minitest::Test
  def test_wait_for_available_item
    q = Libhoney::Queueing::SizedQueueWithTimeout.new
    consumer = Thread.new do
      q.pop
    end
    test_waits_for { consumer.status == 'sleep' }
    q.push 'hello'
    assert_equal('hello', consumer.value)
  end

  def test_popping_a_nil
    q = Libhoney::Queueing::SizedQueueWithTimeout.new
    consumer = Thread.new do
      q.pop
    end
    test_waits_for { consumer.status == 'sleep' }
    q.push nil
    assert_nil consumer.value
  end

  def test_timeout_waiting_for_item
    q = Libhoney::Queueing::SizedQueueWithTimeout.new
    assert_raises Libhoney::Queueing::SizedQueueWithTimeout::PopTimedOut do
      q.pop(0.001)
    end
  end

  def test_timeout_with_custom_timeout_policy
    q = Libhoney::Queueing::SizedQueueWithTimeout.new

    # instead of raising a timeout exception, return a default value
    result = q.pop(0.001) { :and_now_for_something_completely_different }
    assert_equal :and_now_for_something_completely_different, result

    # allow caller to provide a custom exception
    exception = assert_raises StandardError do
      q.pop(0.001) { raise StandardError, 'some custom business logic error' }
    end
    assert_equal 'some custom business logic error', exception.message
  end
end

class PushToSizedQueueWithTimeoutTest < Minitest::Test
  def test_timeout_waiting_for_space
    size_limit = 5
    q = Libhoney::Queueing::SizedQueueWithTimeout.new(size_limit)
    size_limit.times do |n|
      q.push(n)
    end
    assert q.send(:full?)
    assert_raises Libhoney::Queueing::SizedQueueWithTimeout::PushTimedOut do
      q.push(:nope, 0.001)
    end
  end

  def test_timeout_with_custom_timeout_policy
    size_limit = 5
    q = Libhoney::Queueing::SizedQueueWithTimeout.new(size_limit)
    size_limit.times do |n|
      q.push(n)
    end
    assert q.send(:full?)

    # allow caller to provide a custom exception
    exception = assert_raises StandardError do
      q.push(:nope, 0.001) { raise StandardError, 'some custom business logic error' }
    end
    assert_equal 'some custom business logic error', exception.message
  end

  def test_wait_for_available_space
    size_limit = 3

    q = Libhoney::Queueing::SizedQueueWithTimeout.new(
      size_limit,
      lock: FakeLock.new,
      space_available_condition: space_available = FakeCondition.new,
      item_available_condition: FakeCondition.new
    )

    # some pretend threads to control timing
    producer = SyncThread.new
    consumer = SyncThread.new

    # have the item producer fill the queue to its limit
    producer.run(ignore: [:signal]) do
      size_limit.times do |n|
        q.push "item #{n + 1}"
      end
    end
    # the "thread" was able to go all of its work without waiting
    assert producer.finished?

    # have the item producer try to add something to the full queue
    producer.run(ignore: [:signal]) do
      q.push "item #{size_limit + 1}"
    end
    # the producer is told to wait for space available
    assert producer.interrupted_by?(space_available, :wait)

    # take one thing out of the queue
    consumer.run do
      q.pop
    end
    # confirm the consumer "sends" a signal that space is available
    assert consumer.interrupted_by?(space_available, :signal)
    consumer.finish

    # confirm that the producer is able to finish its work after resuming
    # from its wait
    assert producer.resume(ignore: [:signal]).finished?

    # eat the rest of the items on the queue
    consumer.run(ignore: [:signal]) do
      size_limit.times.map { q.pop }
    end
    # confirm we get the rest of the items
    assert_equal(['item 2', 'item 3', 'item 4'], consumer.last_return_value)
  end
end

class ClearASizedQueueWithTimeoutTest < Minitest::Test
  def test_clearing_a_queue
    size_limit = 5
    q = Libhoney::Queueing::SizedQueueWithTimeout.new(size_limit)
    size_limit.times do |n|
      q.push(n)
    end
    assert q.send(:full?)
    q.clear
    assert q.instance_variable_get(:@items).empty?
  end

  def test_clear_signals_space_is_available
    size_limit = 3

    q = Libhoney::Queueing::SizedQueueWithTimeout.new(
      size_limit,
      lock: FakeLock.new,
      space_available_condition: space_available = FakeCondition.new,
      item_available_condition: FakeCondition.new
    )

    # some pretend threads to control timing
    producer = SyncThread.new
    consumer = SyncThread.new

    # have the item producer fill the queue to its limit with things
    # we're going to clear
    producer.run(ignore: [:signal]) do
      size_limit.times do
        q.push :you_should_never_see_any_of_me
      end
    end
    # the "thread" was able to do all of its work without waiting
    assert producer.finished?

    # have the item producer try to add something to the full queue
    producer.run(ignore: [:signal]) do
      q.push :only_i_matter
    end
    # the producer is told to wait for space available
    assert producer.interrupted_by?(space_available, :wait)
    # it's full, right?
    assert q.send(:full?)

    # clear the full queue
    consumer.run do
      q.clear
    end
    # confirm the consumer "sends" a signal that space is available
    assert consumer.interrupted_by?(space_available, :signal)
    consumer.finish
    # it's empty now, yeah?
    assert q.send(:empty?)

    # resume the producer from it's wait-for-space sleep and confirm
    # it finished
    assert producer.resume(ignore: [:signal]).finished?

    # pop the one item that should now be on the queue
    consumer.run(ignore: [:signal]) do
      q.pop
    end
    # confirm we got the one item and not all the things cleared from the queue
    assert_equal(:only_i_matter, consumer.last_return_value)
    assert q.send(:empty?)
  end
end

class FakeCondition
  def wait(timeout)
    SyncThread.interrupt(self, :wait, timeout)
  end

  def signal
    SyncThread.interrupt(self, :signal)
  end
end

class FakeLock
  def synchronize
    yield
  end
end
