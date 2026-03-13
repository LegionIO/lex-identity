# frozen_string_literal: true

require 'legion/extensions/identity/client'

RSpec.describe Legion::Extensions::Identity::Runners::Identity do
  let(:client) { Legion::Extensions::Identity::Client.new }

  describe '#observe_behavior' do
    it 'records a single observation' do
      result = client.observe_behavior(dimension: :communication_cadence, value: 0.7)
      expect(result[:recorded]).to be true
      expect(result[:observation_count]).to eq(1)
    end
  end

  describe '#observe_all' do
    it 'records multiple observations' do
      result = client.observe_all(observations: {
                                    communication_cadence: 0.6,
                                    vocabulary_patterns:   0.7,
                                    emotional_response:    0.5
                                  })
      expect(result[:dimensions_observed].size).to eq(3)
      expect(result[:observation_count]).to eq(3)
    end
  end

  describe '#check_entropy' do
    it 'returns entropy classification' do
      result = client.check_entropy
      expect(result[:entropy]).to be_between(0.0, 1.0)
      expect(result).to have_key(:classification)
      expect(result).to have_key(:trend)
      expect(result).to have_key(:in_range)
    end

    it 'warns on high entropy observations' do
      # Build baseline
      20.times { client.observe_behavior(dimension: :communication_cadence, value: 0.5) }
      # Check with very different observation
      result = client.check_entropy(observations: { communication_cadence: 10.0 })
      expect(result[:warning]).to eq(:possible_impersonation_or_drift) if result[:classification] == :high_entropy
    end
  end

  describe '#identity_status' do
    it 'returns model state' do
      status = client.identity_status
      expect(status).to have_key(:model)
      expect(status).to have_key(:maturity)
      expect(status).to have_key(:observation_count)
    end
  end

  describe '#identity_maturity' do
    it 'returns maturity level' do
      result = client.identity_maturity
      expect(result[:maturity]).to eq(:nascent)
    end
  end
end
