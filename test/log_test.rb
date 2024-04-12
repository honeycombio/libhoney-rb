require 'test_helper'
require 'stringio'
require 'libhoney'

class LibhoneyLogClientTest < Minitest::Test
  def setup
    @output = StringIO.new
    @libhoney = Libhoney::LogClient.new(output: @output)
  end

  class ValueWithEventDuringTransmission
    def initialize(libhoney)
      @libhoney = libhoney
    end

    # to_s gets called by Libhoney::Cleaner on field values synchronously before logging, so if an
    # instance of this class is assigned to a field on an outer event, the inner event will be
    # generated from within the Libhoney::LogTransmissionClient
    def to_s
      event.send
      'value'
    end

    def event
      event = @libhoney.event
      event.add_field('name', 'inner')
      event
    end
  end

  def test_event_during_transmission
    event = @libhoney.event
    event.add_field('name', 'outer')
    event.add_field('field', ValueWithEventDuringTransmission.new(@libhoney))
    event.send
    @libhoney.close
    assert_equal('{"name":"outer","field":"value"}', @output.string.strip)
  end

  class ValueWithInfiniteEventsDuringTransmission < ValueWithEventDuringTransmission
    def event
      event = super
      event.add_field('self', self) # self.to_s triggers yet another event when *this* event gets sent
      event
    end
  end

  def test_infinite_events_during_transmission
    event = @libhoney.event
    event.add_field('name', 'outer')
    event.add_field('field', ValueWithInfiniteEventsDuringTransmission.new(@libhoney))
    event.send # SystemStackError is raised here unless events are prevented during transmission
    @libhoney.close
    assert_equal('{"name":"outer","field":"value"}', @output.string.strip)
  end
end
