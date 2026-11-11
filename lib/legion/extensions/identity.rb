# frozen_string_literal: true

require 'legion/logging'
require 'legion/extensions/identity/version'
require 'legion/extensions/identity/helpers/provider'

module Legion
  module Extensions
    module Identity
      extend Legion::Extensions::Core if Legion::Extensions.const_defined?(:Core, false)

      def self.identity_provider? = false
      def self.remote_invocable? = false
      def self.transport_required? = false
      def self.crypt_required? = false
    end
  end
end
