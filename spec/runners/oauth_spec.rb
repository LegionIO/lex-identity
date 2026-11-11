# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/identity/runners/base/oauth'

RSpec.describe Legion::Extensions::Identity::Runners::Oauth do
  let(:client) do
    Object.new.extend(Legion::Extensions::Identity::Helpers::Oauth).extend(described_class)
  end

  describe 'OAuth grants' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    before do
      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &configure|
        original.call(*args) do |connection|
          configure&.call(connection)
          connection.adapter :test, stubs
        end
      end
    end

    it 'requests a device challenge using provider-neutral form fields' do
      stubs.post('/device') do |request|
        expect(URI.decode_www_form(request.body).to_h).to eq('client_id' => 'client', 'scope' => 'openid profile')
        [200, {}, '{"device_code":"device","user_code":"user","verification_uri":"https://idp/verify"}']
      end

      result = client.request_device_code(device_authorization_endpoint: 'https://idp/device', client_id: 'client', scope: 'openid profile')
      expect(result).to eq(result: { device_code: 'device', user_code: 'user', verification_uri: 'https://idp/verify' })
    end

    it 'exchanges a PKCE code without corrupting reserved characters' do
      stubs.post('/token') do |request|
        expect(URI.decode_www_form(request.body).to_h).to eq(
          'grant_type' => 'authorization_code', 'client_id' => 'client', 'code' => 'code+proof',
          'redirect_uri' => 'https://app/callback?from=login', 'code_verifier' => 'verifier', 'scope' => 'openid profile'
        )
        [200, {}, '{"access_token":"access","refresh_token":"refresh"}']
      end

      result = client.exchange_code(token_endpoint: 'https://idp/token', client_id: 'client', code: 'code+proof',
                                    redirect_uri: 'https://app/callback?from=login', code_verifier: 'verifier', scope: 'openid profile')
      expect(result).to eq(result: { access_token: 'access', refresh_token: 'refresh' })
    end

    it 'refreshes without sending an unspecified scope' do
      stubs.post('/token') do |request|
        expect(URI.decode_www_form(request.body).to_h).to eq(
          'grant_type' => 'refresh_token', 'client_id' => 'client', 'refresh_token' => 'refresh'
        )
        [200, {}, '{"access_token":"renewed"}']
      end

      expect(client.refresh_token(token_endpoint: 'https://idp/token', client_id: 'client', refresh_token: 'refresh'))
        .to eq(result: { access_token: 'renewed' })
    end

    it 'returns provider rejections as errors rather than successful results' do
      stubs.post('/token') { [400, {}, '{"error":"invalid_grant","error_description":"expired"}'] }

      expect(client.refresh_token(token_endpoint: 'https://idp/token', client_id: 'client', refresh_token: 'refresh'))
        .to eq(error: 'invalid_grant', description: 'expired')
    end

    it 'rejects a blank token even on HTTP success' do
      stubs.post('/token') { [200, {}, '{"access_token":""}'] }

      expect(client.exchange_code(token_endpoint: 'https://idp/token', client_id: 'client', code: 'code',
                                  redirect_uri: 'https://app/callback', code_verifier: 'verifier'))
        .to include(error: 'invalid_response')
    end

    it 'rejects a device response without a device code' do
      stubs.post('/device') { [200, {}, '{}'] }

      expect(client.request_device_code(device_authorization_endpoint: 'https://idp/device', client_id: 'client', scope: 'openid'))
        .to include(error: 'invalid_response')
    end
  end

  describe '#poll_device_code' do
    it 'waits for pending responses and accumulates provider slow-down requests' do
      allow(client).to receive(:oauth_post).and_return(
        { error: 'authorization_pending' }, { error: 'slow_down' }, { error: 'slow_down' }, { access_token: 'access' }
      )
      elapsed = 0
      waits = []
      allow(client).to receive(:oauth_monotonic_now) { elapsed }
      allow(client).to receive(:sleep) { |seconds|
        waits << seconds
        elapsed += seconds
      }

      result = client.poll_device_code(token_endpoint: 'https://idp/token', client_id: 'client', device_code: 'device',
                                       interval: 1, timeout: 30)

      expect(waits).to eq([1, 6, 11])
      expect(result).to eq(result: { access_token: 'access' })
    end

    it 'caps the final wait and network timeouts at the remaining deadline' do
      allow(client).to receive(:oauth_post).and_return(error: 'authorization_pending')
      allow(client).to receive(:oauth_monotonic_now).and_return(0, 0, 1, 3)
      allow(client).to receive(:sleep)

      result = client.poll_device_code(token_endpoint: 'https://idp/token', client_id: 'client', device_code: 'device',
                                       interval: 10, timeout: 3)

      expect(client).to have_received(:oauth_post).with(
        endpoint: 'https://idp/token', form: { grant_type: described_class::DEVICE_CODE_GRANT, client_id: 'client', device_code: 'device' },
        open_timeout: 3, request_timeout: 3
      ).once
      expect(client).to have_received(:sleep).with(2).once
      expect(result[:error]).to eq('timeout')
    end

    it 'terminates with invalid_response when a token endpoint returns neither a token nor an error' do
      allow(client).to receive(:oauth_post).and_return({})

      expect(client.poll_device_code(token_endpoint: 'https://idp/token', client_id: 'client', device_code: 'device'))
        .to include(error: 'invalid_response')
    end

    it 'does not poll after a zero deadline or accept a nonpositive interval' do
      allow(client).to receive(:oauth_post)
      expect(client.poll_device_code(token_endpoint: 'https://idp/token', client_id: 'client', device_code: 'device', timeout: 0))
        .to include(error: 'timeout')
      expect(client).not_to have_received(:oauth_post)
      expect do
        client.poll_device_code(token_endpoint: 'https://idp/token', client_id: 'client', device_code: 'device', interval: 0)
      end.to raise_error(ArgumentError)
      expect do
        client.poll_device_code(token_endpoint: 'https://idp/token', client_id: 'client', device_code: 'device', timeout: -1)
      end.to raise_error(ArgumentError)
    end
  end
end
