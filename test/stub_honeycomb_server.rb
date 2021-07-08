require 'sinatra/base'
require 'sinatra/json'

class StubHoneycombServer < Sinatra::Base
  set :json_encoder, :to_json

  before do
    @batch = JSON.parse(request.body.read.to_s)
  end

  # post to the batch endpoint with any dataset
  # receive successes for all events in the batch
  post '/1/batch/:dataset' do
    json(@batch.map { { status: 202 } })
  end
end
