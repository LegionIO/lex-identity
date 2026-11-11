# frozen_string_literal: true

module Legion
  module Extensions
    module Identity
      module Helpers
        module Provider
          def identity_register(**)
            if defined?(Legion::Identity::Resolver) && Legion::Identity::Resolver.respond_to?(:register)
              Legion::Identity::Resolver.register(self)
              :registered
            elsif defined?(Legion::Identity) &&
                  Legion::Identity.respond_to?(:pending_registrations) &&
                  Legion::Identity.pending_registrations.respond_to?(:<<)
              Legion::Identity.pending_registrations << self
              :pending
            else
              :unavailable
            end
          end

          def identity_build_lease(credential:, **attributes)
            attributes = attributes.merge(provider: provider_name, credential: credential)
            return attributes unless defined?(Legion::Identity::Lease)

            Legion::Identity::Lease.new(**attributes)
          end

          def identity_register_credential(lease:, qualifier: :default, default: false, **)
            unless defined?(Legion::Identity::Broker) && Legion::Identity::Broker.respond_to?(:register_provider)
              raise 'Credential registration requires Legion::Identity::Broker'
            end

            Legion::Identity::Broker.register_provider(provider_name, provider: self, lease: lease, qualifier: qualifier, default: default)
          end

          def identity_credentials_available(**)
            return [] unless defined?(Legion::Identity::Broker)

            Legion::Identity::Broker.credentials_available(provider_name)
          end

          def identity_token_for(qualifier: nil, **)
            return nil unless defined?(Legion::Identity::Broker)

            Legion::Identity::Broker.token_for(provider_name, qualifier: qualifier, **)
          end
        end
      end
    end
  end
end
