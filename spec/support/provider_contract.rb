# frozen_string_literal: true

RSpec.shared_examples 'identity provider contract' do
  let(:canonical_name) { 'example-user' }

  it 'exposes provider metadata with contract types' do
    provider = identity_provider

    expect(provider.provider_name).to be_a(Symbol)
    expect(%i[auth profile fallback]).to include(provider.provider_type)
    expect(provider.priority).to be_a(Numeric)
    expect(provider.trust_weight).to be_a(Numeric)
    expect(provider.capabilities).to be_an(Array)
    expect(provider.capabilities).to all(be_a(Symbol))

    trust_levels = if defined?(Legion::Identity::Trust) && Legion::Identity::Trust.respond_to?(:levels)
                     Legion::Identity::Trust.levels
                   else
                     %i[verified authenticated configured cached unverified]
                   end
    expect(trust_levels).to include(provider.trust_level)
  end

  it 'uses the core resolution call contract' do
    provider = identity_provider
    result = case provider.provider_type
             when :profile
               if provider.respond_to?(:resolve_all)
                 provider.resolve_all(canonical_name: canonical_name)
               else
                 provider.resolve(canonical_name: canonical_name)
               end
             when :auth, :fallback
               provider.resolve
             end

    expect(result).to be_nil.or be_a(Hash)
    next if result.nil?

    if %i[auth fallback].include?(provider.provider_type)
      expect(result).to include(:canonical_name, :kind, :source)
      expect(result[:canonical_name]).to match(/\A[a-z0-9][a-z0-9_-]*\z/)
      expect(result[:kind]).not_to be_nil
      expect(result[:source]).not_to be_nil
    else
      expect(result).not_to have_key(:canonical_name)
    end
  end
end
