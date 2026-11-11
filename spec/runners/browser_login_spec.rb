# frozen_string_literal: true

require 'digest'
require 'net/http'
require 'socket'
require 'uri'
require 'spec_helper'
require 'legion/extensions/identity/runners/base/oauth'

RSpec.describe Legion::Extensions::Identity::Runners::Oauth, '#browser_login' do
  let(:client) do
    Object.new
          .extend(Legion::Extensions::Identity::Helpers::Oauth)
          .extend(Legion::Extensions::Identity::Helpers::Pkce)
          .extend(Legion::Extensions::Identity::Helpers::Browser)
          .extend(described_class)
  end
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:browser_threads) { [] }
  let(:callback_responses) { Queue.new }
  let(:last_authorization) { {} }

  before do
    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &configure|
      original.call(*args) do |connection|
        configure&.call(connection)
        connection.adapter :test, stubs
      end
    end
    allow(client).to receive(:browser_gui_available?).and_return(true)
  end

  after do
    browser_threads.each do |thread|
      finished = thread.join(3)
      thread.kill unless finished
      thread.join
      raise 'Browser fixture did not finish' unless finished

      thread.value
    end
  end

  def launch_browser_callback(query:)
    allow(client).to receive(:browser_open) do |url:|
      authorization = URI.parse(url)
      params = URI.decode_www_form(authorization.query).to_h
      last_authorization.merge!(params)
      callback_uri = URI.parse(params.fetch('redirect_uri'))
      callback_uri.query = URI.encode_www_form(query.merge('state' => params.fetch('state')))
      browser_threads << Thread.new do
        response = Net::HTTP.start(callback_uri.host, callback_uri.port, open_timeout: 2, read_timeout: 2) do |http|
          http.get(callback_uri.request_uri)
        end
        callback_responses << response
      end
      true
    end
  end

  def wait_for_browser_response
    response = callback_responses.pop(timeout: 3)
    expect(response).to be_a(Net::HTTPResponse)
  end

  def callback_port
    URI.parse(last_authorization.fetch('redirect_uri')).port
  end

  def expect_callback_listener_closed
    expect { TCPSocket.open('127.0.0.1', callback_port, &:close) }
      .to raise_error(Errno::ECONNREFUSED)
  end

  it 'performs PKCE authorization and exchanges the callback code with the same redirect URI' do
    launch_browser_callback(query: { 'code' => 'auth-code' })
    stubs.post('/token') do |request|
      form = URI.decode_www_form(request.body).to_h
      challenge = [Digest::SHA256.digest(form.fetch('code_verifier'))].pack('m0').tr('+/', '-_').delete('=')
      expect(last_authorization.fetch('code_challenge')).to eq(challenge)
      expect(form.fetch('redirect_uri')).to eq(last_authorization.fetch('redirect_uri'))
      expect(form.fetch('scope')).to eq('openid profile')
      [200, {}, '{"access_token":"access-token"}']
    end

    result = client.browser_login(authorization_endpoint: 'https://idp/authorize', token_endpoint: 'https://idp/token',
                                  client_id: 'client', scope: 'openid profile')

    expect(result).to eq(result: { access_token: 'access-token' })
    wait_for_browser_response
    expect(last_authorization.fetch('code_challenge_method')).to eq('S256')
    expect_callback_listener_closed
  end

  it 'does not exchange a provider denial and closes the callback listener' do
    launch_browser_callback(query: { 'error' => 'access_denied', 'error_description' => 'cancelled' })
    token_calls = 0
    stubs.post('/token') do
      token_calls += 1
      [200, {}, '{"access_token":"unexpected"}']
    end

    result = client.browser_login(authorization_endpoint: 'https://idp/authorize', token_endpoint: 'https://idp/token',
                                  client_id: 'client', scope: 'openid')

    expect(result).to eq(error: 'access_denied', description: 'cancelled')
    expect(token_calls).to eq(0)
    wait_for_browser_response
    expect_callback_listener_closed
  end

  it 'returns browser launch failure and closes the callback listener' do
    allow(client).to receive(:browser_open) do |url:|
      last_authorization.merge!(URI.decode_www_form(URI.parse(url).query).to_h)
      false
    end

    result = client.browser_login(authorization_endpoint: 'https://idp/authorize', token_endpoint: 'https://idp/token',
                                  client_id: 'client', scope: 'openid')

    expect(result).to eq(error: 'browser_launch_failed', description: 'Unable to launch the browser')
    expect_callback_listener_closed
  end

  it 'returns timeout and closes the callback listener' do
    allow(client).to receive(:browser_open) do |url:|
      last_authorization.merge!(URI.decode_www_form(URI.parse(url).query).to_h)
      true
    end

    result = client.browser_login(authorization_endpoint: 'https://idp/authorize', token_endpoint: 'https://idp/token',
                                  client_id: 'client', scope: 'openid', callback_timeout: 0.05)

    expect(result[:error]).to eq('timeout')
    expect_callback_listener_closed
  end

  it 'closes the callback listener when token exchange fails' do
    launch_browser_callback(query: { 'code' => 'auth-code' })
    stubs.post('/token') { [400, {}, '{"error":"invalid_grant","error_description":"rejected"}'] }

    result = client.browser_login(authorization_endpoint: 'https://idp/authorize', token_endpoint: 'https://idp/token',
                                  client_id: 'client', scope: 'openid')

    expect(result).to eq(error: 'invalid_grant', description: 'rejected')
    wait_for_browser_response
    expect_callback_listener_closed
  end

  it 'returns browser unavailable before opening a callback listener' do
    allow(client).to receive(:browser_gui_available?).and_return(false)
    expect(Legion::Extensions::Identity::Helpers::CallbackServer).not_to receive(:new)

    result = client.browser_login(authorization_endpoint: 'https://idp/authorize', token_endpoint: 'https://idp/token',
                                  client_id: 'client', scope: 'openid')

    expect(result).to eq(error: 'browser_unavailable', description: 'Interactive browser login requires a graphical session')
  end

  it 'rejects invalid callback timeouts before checking browser availability' do
    expect(client).not_to receive(:browser_gui_available?)
    expect(Legion::Extensions::Identity::Helpers::CallbackServer).not_to receive(:new)

    expect do
      client.browser_login(authorization_endpoint: 'https://idp/authorize', token_endpoint: 'https://idp/token',
                           client_id: 'client', scope: 'openid', callback_timeout: Float::NAN)
    end.to raise_error(ArgumentError, 'callback_timeout must be positive and finite')
  end
end
