require 'libhoney/client'
require 'libhoney/log_client'
require 'libhoney/null_client'
require 'libhoney/test_client'
require 'libhoney/version'
require 'libhoney/builder'
require 'libhoney/response'
require 'libhoney/transmission'

module Libhoney
  def self.classic_write_key?(write_key)
    write_key.nil? ||
      write_key.match(/\A[[:alnum:]]{32}\z/) ||
      write_key.match(/\Ahc[a-z]ic_[[:alnum:]]{58}\z/)
  end
end
