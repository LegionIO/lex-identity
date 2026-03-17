# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/identity/helpers/graph_token'

RSpec.describe Legion::Extensions::Identity::Helpers::GraphToken do
  describe '.fetch' do
    it 'raises GraphTokenError on failure' do
      stub_request = instance_double(Faraday::Response, success?: false,
                                                        body:     { 'error_description' => 'invalid_client' })
      conn = instance_double(Faraday::Connection)
      allow(conn).to receive(:post).and_return(stub_request)
      allow(Faraday).to receive(:new).and_return(conn)

      expect do
        described_class.fetch(tenant_id: 't1', client_id: 'c1', client_secret: 's1')
      end.to raise_error(described_class::GraphTokenError, 'invalid_client')
    end

    it 'returns access_token on success' do
      stub_request = instance_double(Faraday::Response, success?: true,
                                                        body:     { 'access_token' => 'tok-123' })
      conn = instance_double(Faraday::Connection)
      allow(conn).to receive(:post).and_return(stub_request)
      allow(Faraday).to receive(:new).and_return(conn)

      token = described_class.fetch(tenant_id: 't1', client_id: 'c1', client_secret: 's1')
      expect(token).to eq('tok-123')
    end
  end
end
