# frozen_string_literal: true

require 'digest'
require 'securerandom'

module Legion
  module Extensions
    module Identity
      module Helpers
        module Pkce
          def pkce_generate(**)
            verifier = SecureRandom.hex(32)
            challenge = [Digest::SHA256.digest(verifier)].pack('m0').tr('+/', '-_').delete('=')
            { code_verifier: verifier, code_challenge: challenge, code_challenge_method: 'S256' }
          end
        end
      end
    end
  end
end
