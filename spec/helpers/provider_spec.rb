# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Identity::Helpers::Provider do
  let(:identity_provider) do
    Class.new do
      extend Legion::Extensions::Identity::Helpers::Provider

      def self.provider_name
        :fixture
      end
    end
  end

  describe '#identity_build_lease' do
    it 'returns standalone attributes with provider provenance' do
      stub_const('Legion::Identity', Module.new)

      lease = identity_provider.identity_build_lease(
        credential: 'secret',
        provider:   :untrusted,
        lease_id:   'lease-1',
        metadata:   { source: :fixture }
      )

      expect(lease).to eq(
        provider:   :fixture,
        credential: 'secret',
        lease_id:   'lease-1',
        metadata:   { source: :fixture }
      )
    end
  end

  describe '#identity_register' do
    it 'allows standalone provider loading without a core registry' do
      hide_const('Legion::Identity')

      expect(identity_provider.identity_register).to eq(:unavailable)
    end

    it 'preserves earlier providers when appending to the core pending queue' do
      pending = [Object.new]
      original = pending.first
      core = Module.new
      core.define_singleton_method(:pending_registrations) { pending }
      stub_const('Legion::Identity', core)

      expect(identity_provider.identity_register).to eq(:pending)
      expect(pending).to eq([original, identity_provider])
    end
  end

  describe '#identity_register_credential' do
    it 'raises a clear error when Broker is unavailable' do
      stub_const('Legion::Identity', Module.new)

      expect do
        identity_provider.identity_register_credential(lease: { credential: 'secret' })
      end.to raise_error(RuntimeError, /requires Legion::Identity::Broker/)
    end
  end

  describe '#identity_credentials_available' do
    it 'returns no credentials before Broker is loaded' do
      stub_const('Legion::Identity', Module.new)

      expect(identity_provider.identity_credentials_available).to eq([])
    end
  end

  describe '#identity_token_for' do
    it 'returns no token before Broker is loaded' do
      stub_const('Legion::Identity', Module.new)

      expect(identity_provider.identity_token_for(purpose: :test)).to be_nil
    end
  end
end
