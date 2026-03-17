# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/identity/helpers/graph_client'

RSpec.describe Legion::Extensions::Identity::Helpers::GraphClient do
  describe '.connection' do
    it 'returns a Faraday connection with bearer token' do
      conn = described_class.connection(token: 'test-token')
      expect(conn).to be_a(Faraday::Connection)
      expect(conn.headers['Authorization']).to eq('Bearer test-token')
    end

    it 'uses custom base URL when provided' do
      conn = described_class.connection(token: 'tok', base: 'https://custom.api.com')
      expect(conn.url_prefix.to_s).to eq('https://custom.api.com/')
    end
  end
end
