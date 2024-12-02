require 'sinatra/base'
require 'sinatra/json'

class StubHoneycombServer < Sinatra::Base
  set :json_encoder, :to_json
  set :host_authorization, { permitted_hosts: [] }

  before do
    @batch = JSON.parse(request.body.read.to_s)
  end

  post '/1/batch/:dataset' do
    case params['dataset']
    when 'err-bad-key'
      [400, json(error: 'unknown API key - check your credentials')]
    when 'err-too-big'
      [400, json(error: 'request body is too large')]
    when 'err-malformed'
      [400, json(error: 'request body is malformed and cannot be read as JSON')]
    when 'err-throttled'
      [403, json(error: 'event dropped due to administrative throttling')]
    when 'err-admin-blocklist'
      [429, json(error: 'event dropped due to administrative blacklist')]
    when 'err-rate-limited'
      [429, json(error: 'request dropped due to rate limiting')]
    else
      json(@batch.map { { status: 202 } })
    end
  end
end
