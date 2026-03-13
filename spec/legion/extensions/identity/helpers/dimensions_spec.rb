# frozen_string_literal: true

RSpec.describe Legion::Extensions::Identity::Helpers::Dimensions do
  describe '.new_identity_model' do
    it 'creates a model with 6 dimensions' do
      model = described_class.new_identity_model
      expect(model.size).to eq(6)
      described_class::IDENTITY_DIMENSIONS.each do |dim|
        expect(model[dim][:mean]).to eq(0.5)
      end
    end
  end

  describe '.compute_entropy' do
    it 'returns 0.5 for empty observations' do
      model = described_class.new_identity_model
      expect(described_class.compute_entropy({}, model)).to eq(0.5)
    end

    it 'returns low entropy for observations matching baseline' do
      model = described_class.new_identity_model
      model[:communication_cadence][:observations] = 50
      obs = { communication_cadence: 0.5 }
      entropy = described_class.compute_entropy(obs, model)
      expect(entropy).to be < 0.3
    end

    it 'returns high entropy for observations diverging from baseline' do
      model = described_class.new_identity_model
      model[:communication_cadence][:observations] = 50
      model[:communication_cadence][:variance] = 0.1
      obs = { communication_cadence: 1.0 }
      entropy = described_class.compute_entropy(obs, model)
      expect(entropy).to be > 0.3
    end
  end

  describe '.classify_entropy' do
    it 'classifies high entropy' do
      expect(described_class.classify_entropy(0.8)).to eq(:high_entropy)
    end

    it 'classifies low entropy' do
      expect(described_class.classify_entropy(0.1)).to eq(:low_entropy)
    end

    it 'classifies normal entropy' do
      expect(described_class.classify_entropy(0.5)).to eq(:normal)
    end
  end
end
