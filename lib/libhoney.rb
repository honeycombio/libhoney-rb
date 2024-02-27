require 'libhoney/client'
require 'libhoney/log_client'
require 'libhoney/null_client'
require 'libhoney/test_client'
require 'libhoney/version'
require 'libhoney/builder'
require 'libhoney/response'
require 'libhoney/transmission'

module Libhoney
  CLASSIC_ORIGINAL_FLAVOR = Regexp.new(/\A[[:alnum:]]{32}\z/)
  CLASSIC_V3_INGEST = Regexp.new(/\Ahc[a-z]ic_[[:alnum:]]{58}\z/)
  # Determines if the given string is a Honeycomb API key for Classic environments.
  #
  # @param api_key [String] the string to check
  # @return [Boolean] true if the string is nil or a classic API key, false otherwise
  def self.classic_api_key?(api_key)
    api_key.nil? || # default to classic behavior if no API key is provided
      CLASSIC_ORIGINAL_FLAVOR.match?(api_key) ||
      CLASSIC_V3_INGEST.match?(api_key)
  end
end
