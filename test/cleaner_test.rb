require 'test_helper'
require 'minitest/mock'
require 'libhoney'
require 'libhoney/cleaner'

class CleanerTest < Minitest::Test
  include Libhoney::Cleaner

  def test_recursive_data
    data = {}
    interesting_data = {}

    data[:test] = interesting_data
    interesting_data[:test] = data

    clean_data = clean_data(data, {})

    assert_equal({ test: '[RECURSION]' }, clean_data)
  end

  def test_invalid_strings
    data = { not_a_good_string: "\x89" }

    clean_data = clean_data(data, {})

    assert_equal({ not_a_good_string: '�' }, clean_data)
  end

  def test_objects_get_stringified
    custom_object = Class.new do
      def to_s
        'A custom object.'
      end
    end

    data = { object_information: custom_object.new }

    clean_data = clean_data(data, {})

    assert_equal({ object_information: 'A custom object.' }, clean_data)
  end

  def test_objects_might_object_to_stringification
    no_string_for_you = Class.new do
      def to_s
        raise StandardError, 'Anything that raises when asked for a string version.'
      end
    end

    data = { object_information: no_string_for_you.new }

    clean_data = clean_data(data, {})

    assert_equal({ object_information: '[RAISED]' }, clean_data)
  end
end
