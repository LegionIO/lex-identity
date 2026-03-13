# frozen_string_literal: true

require 'legion/extensions/identity/client'

RSpec.describe Legion::Extensions::Identity::Client do
  let(:client) { described_class.new }

  it 'responds to identity runner methods' do
    expect(client).to respond_to(:observe_behavior)
    expect(client).to respond_to(:observe_all)
    expect(client).to respond_to(:check_entropy)
    expect(client).to respond_to(:identity_status)
    expect(client).to respond_to(:identity_maturity)
  end

  it 'round-trips identity lifecycle' do
    # Build identity
    50.times do
      client.observe_all(observations: {
                           communication_cadence: 0.5 + (rand * 0.1),
                           vocabulary_patterns:   0.6 + (rand * 0.1),
                           emotional_response:    0.4 + (rand * 0.1)
                         })
    end

    expect(client.identity_maturity[:maturity]).to eq(:established)

    # Check entropy with consistent behavior
    result = client.check_entropy(observations: { communication_cadence: 0.55 })
    expect(result[:entropy]).to be_between(0.0, 1.0)
  end
end
