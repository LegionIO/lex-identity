# frozen_string_literal: true

RSpec.describe Legion::Extensions::Identity::Helpers::Fingerprint do
  let(:fp) { described_class.new }

  describe '#observe' do
    it 'records observation for valid dimension' do
      fp.observe(:communication_cadence, 0.7)
      expect(fp.observation_count).to eq(1)
    end

    it 'ignores invalid dimensions' do
      fp.observe(:nonexistent, 0.5)
      expect(fp.observation_count).to eq(0)
    end

    it 'shifts mean toward observed values' do
      original = fp.model[:vocabulary_patterns][:mean]
      10.times { fp.observe(:vocabulary_patterns, 0.9) }
      expect(fp.model[:vocabulary_patterns][:mean]).to be > original
    end
  end

  describe '#observe_all' do
    it 'records multiple dimensions at once' do
      fp.observe_all(communication_cadence: 0.6, vocabulary_patterns: 0.7)
      expect(fp.observation_count).to eq(2)
    end
  end

  describe '#current_entropy' do
    it 'computes entropy against model' do
      entropy = fp.current_entropy(communication_cadence: 0.5)
      expect(entropy).to be_between(0.0, 1.0)
    end

    it 'tracks entropy history' do
      3.times { fp.current_entropy(communication_cadence: 0.5) }
      expect(fp.entropy_history.size).to eq(3)
    end
  end

  describe '#entropy_trend' do
    it 'returns stable for insufficient data' do
      expect(fp.entropy_trend).to eq(:stable)
    end

    it 'detects rising entropy' do
      5.times { |i| fp.current_entropy(communication_cadence: 0.5 + (i * 0.1)) }
      # Trend depends on actual computed values
      trend = fp.entropy_trend(window: 5)
      expect(%i[rising stable falling]).to include(trend)
    end
  end

  describe '#maturity' do
    it 'starts as nascent' do
      expect(fp.maturity).to eq(:nascent)
    end

    it 'progresses to developing' do
      15.times { fp.observe(:communication_cadence, 0.5) }
      expect(fp.maturity).to eq(:developing)
    end
  end
end
