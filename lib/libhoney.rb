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
    api_key.nil? ||
      api_key.match(/\A[[:alnum:]]{32}\z/) ||
      api_key.match(/\Ahc[a-z]ic_[[:alnum:]]{58}\z/)
  end
end
