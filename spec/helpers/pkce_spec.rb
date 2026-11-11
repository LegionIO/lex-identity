# frozen_string_literal: true

require 'legion/extensions/identity/helpers/pkce'

RSpec.describe Legion::Extensions::Identity::Helpers::Pkce do
  subject(:helper) { Object.new.extend(described_class) }

  it 'produces the RFC 7636 S256 challenge without base64 padding' do
    verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'
    allow(SecureRandom).to receive(:hex).with(32).and_return(verifier)

    expect(helper.pkce_generate).to eq(
      code_verifier:         verifier,
      code_challenge:        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      code_challenge_method: 'S256'
    )
  end
end
