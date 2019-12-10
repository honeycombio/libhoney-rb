require 'stringio'
require 'libhoney/log_transmission'

class LogTransmissionClientTest < Minitest::Test
  def test_cleaned_output
    stdout = StringIO.new
    transmission = Libhoney::LogTransmissionClient.new(output: stdout)
    data = { not_a_good_string: "\x89" }
    transmission.add(OpenStruct.new(data: data))
    assert_equal('{"not_a_good_string":"�"}', stdout.string.strip)
  end
end
