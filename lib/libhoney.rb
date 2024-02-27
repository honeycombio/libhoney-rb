require 'libhoney/client'
require 'libhoney/log_client'
require 'libhoney/null_client'
require 'libhoney/test_client'
require 'libhoney/version'
require 'libhoney/builder'
require 'libhoney/response'
require 'libhoney/transmission'

module Libhoney
  # Determines if the given string is a Honeycomb API key for Classic environments.
  #
  # @param api_key [String] the string to check
  # @return [Boolean] true if the string is nil or a classic API key, false otherwise
  def self.classic_api_key?(api_key)
    api_key.nil? || # default to classic behavior if no API key is provided
      CLASSIC_KEY_ORIGINAL_FLAVOR.match?(api_key) ||
      CLASSIC_KEY_V3_INGEST.match?(api_key)
  end

  # Private constant for key format detection.
  # @api private
  CLASSIC_KEY_ORIGINAL_FLAVOR = Regexp.new(/\A[[:alnum:]]{32}\z/)
  private_constant :CLASSIC_KEY_ORIGINAL_FLAVOR

  # Private constant for key format detection.
  # @api private
  CLASSIC_KEY_V3_INGEST = Regexp.new(/\Ahc[a-z]ic_[[:alnum:]]{58}\z/)
  private_constant :CLASSIC_KEY_V3_INGEST
end
