# frozen_string_literal: true

require 'spec_helper'
require 'faraday'
require 'legion/extensions/identity/helpers/oauth'

RSpec.describe Legion::Extensions::Identity::Helpers::Oauth do
  subject(:client) { Object.new.extend(described_class) }

  it 'preserves unrelated query values but replaces conflicting OAuth parameters' do
    result = client.oauth_authorize_url(
      authorization_endpoint: 'https://idp.example/authorize?audience=login&state=old',
      client_id: 'client id', redirect_uri: 'https://app.example/callback?from=login',
      scope: 'openid profile', state: 'fresh state', code_challenge: 'challenge+/='
    )

    query = URI.decode_www_form(URI.parse(result).query).to_h
    expect(query).to include('audience' => 'login', 'client_id' => 'client id', 'response_type' => 'code',
                             'redirect_uri' => 'https://app.example/callback?from=login', 'scope' => 'openid profile',
                             'state' => 'fresh state', 'code_challenge' => 'challenge+/=', 'code_challenge_method' => 'S256')
  end

  describe '#oauth_post' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    before do
      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &configure|
        original.call(*args) do |connection|
          configure&.call(connection)
          connection.adapter :test, stubs
        end
      end
    end

    it 'sends encoded form data and parses symbol-keyed JSON' do
      stubs.post('/token') do |request|
        expect(request.request_headers['Accept']).to eq('application/json')
        expect(request.request_headers['Content-Type']).to include('application/x-www-form-urlencoded')
        expect(URI.decode_www_form(request.body).to_h).to eq('grant_type' => 'authorization_code', 'code' => 'a + b')
        [200, {}, '{"access_token":"token"}']
      end

      expect(client.oauth_post(endpoint: 'https://idp.example/token', form: { grant_type: 'authorization_code', code: 'a + b' }))
        .to eq(access_token: 'token')
    end

    it 'preserves the provider rejection instead of replacing it with an HTTP status' do
      stubs.post('/token') { [400, {}, '{"error":"invalid_grant","error_description":"expired"}'] }

      expect(client.oauth_post(endpoint: 'https://idp.example/token', form: {}))
        .to eq(error: 'invalid_grant', error_description: 'expired')
    end

    it 'preserves HTTP failure status when an upstream proxy returns HTML' do
      stubs.post('/token') { [503, {}, '<html>unavailable</html>'] }

      expect(client.oauth_post(endpoint: 'https://idp.example/token', form: {})).to include(error: 'http_503')
    end

    it 'rejects a successful non-object JSON response' do
      stubs.post('/token') { [200, {}, '["not-a-token-object"]'] }

      expect(client.oauth_post(endpoint: 'https://idp.example/token', form: {})).to include(error: 'invalid_response')
    end

    it 'does not invent credentials for an empty successful response' do
      stubs.post('/token') { [204, {}, ''] }

      expect(client.oauth_post(endpoint: 'https://idp.example/token', form: {})).to eq({})
    end
  end
end
