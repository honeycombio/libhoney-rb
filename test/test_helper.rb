require 'minitest/autorun'
require 'minitest/reporters'
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new, Minitest::Reporters::JUnitReporter.new]

def test_waits_for(timeout = 1)
  Timeout.timeout timeout do
    sleep 0.001 until yield
  end
end
