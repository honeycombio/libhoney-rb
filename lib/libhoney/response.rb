require 'http'

module Libhoney
  class Response
    attr_accessor :duration, :status_code, :metadata, :error

    def initialize(duration: 0,
                   status_code: 0,
                   metadata: nil,
                   error: nil)
      @duration    = duration
      @status_code = HTTP::Response::Status.new(status_code)
      @metadata    = metadata
      @error       = error
    end
  end
end
