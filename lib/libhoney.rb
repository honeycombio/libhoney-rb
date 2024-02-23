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
      write_key.length == 32 ||
      write_key =~ /^hc[a-z]ic_[[:alnum:]]{58}$/
  end
end
