# frozen_string_literal: true

require 'legion/extensions/identity/helpers/dimensions'
require 'legion/extensions/identity/helpers/fingerprint'
require 'legion/extensions/identity/runners/identity'

module Legion
  module Extensions
    module Identity
      class Client
        include Runners::Identity

        def initialize(**)
          @identity_fingerprint = Helpers::Fingerprint.new
        end

        private

        attr_reader :identity_fingerprint
      end
    end
  end
end
