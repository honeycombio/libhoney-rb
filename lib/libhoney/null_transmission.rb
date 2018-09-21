module Libhoney
  # A no-op version of TransmissionClient that silently drops events (without
  # sending them to Honeycomb, or anywhere else for that matter).
  #
  # @api private
  class NullTransmissionClient
    def add(event); end

    def close(drain); end
  end
end
