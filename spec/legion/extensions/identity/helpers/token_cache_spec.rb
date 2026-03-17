# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/identity/helpers/token_cache'

RSpec.describe Legion::Extensions::Identity::Helpers::TokenCache do
  before { described_class.clear_all }
  after { described_class.clear_all }

  describe '.store and .fetch' do
    it 'stores and retrieves a token' do
      described_class.store(worker_id: 'w1', token: 'abc', expires_in: 3600)
      entry = described_class.fetch(worker_id: 'w1')
      expect(entry[:access_token]).to eq('abc')
    end

    it 'returns nil for unknown worker' do
      expect(described_class.fetch(worker_id: 'unknown')).to be_nil
    end

    it 'returns nil for expired token' do
      described_class.store(worker_id: 'w1', token: 'abc', expires_in: -1)
      expect(described_class.fetch(worker_id: 'w1')).to be_nil
    end
  end

  describe '.approaching_expiry?' do
    it 'returns true when no token exists' do
      expect(described_class.approaching_expiry?(worker_id: 'w1')).to be true
    end

    it 'returns true when token is within buffer' do
      described_class.store(worker_id: 'w1', token: 'abc', expires_in: 100)
      expect(described_class.approaching_expiry?(worker_id: 'w1', buffer: 200)).to be true
    end

    it 'returns false when token has plenty of time' do
      described_class.store(worker_id: 'w1', token: 'abc', expires_in: 3600)
      expect(described_class.approaching_expiry?(worker_id: 'w1', buffer: 300)).to be false
    end
  end

  describe '.clear' do
    it 'removes a specific worker token' do
      described_class.store(worker_id: 'w1', token: 'abc', expires_in: 3600)
      described_class.clear(worker_id: 'w1')
      expect(described_class.fetch(worker_id: 'w1')).to be_nil
    end
  end
end
