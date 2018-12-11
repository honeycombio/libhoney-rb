require 'minitest/autorun'
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

  def test_objects
    data = { object_information: CustomObject.new }

    clean_data = clean_data(data, {})

    assert_includes(clean_data.keys, :object_information)
  end

  class CustomObject
  end
end
