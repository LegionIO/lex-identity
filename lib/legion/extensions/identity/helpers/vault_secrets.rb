# frozen_string_literal: true

module Legion
  module Extensions
    module Identity
      module Helpers
        # Vault secret path conventions for Digital Worker Entra ID credentials.
        #
        # Secrets are stored in Vault KV v2 under a well-known path:
        #   secret/data/legion/workers/{worker_id}/entra
        #
        # Legion uses legion-crypt for Vault access. If Vault is not connected,
        # methods return nil/false gracefully.
        module VaultSecrets
          VAULT_PATH_PREFIX = 'secret/data/legion/workers'

          def self.secret_path(worker_id)
            "#{VAULT_PATH_PREFIX}/#{worker_id}/entra"
          end

          # Store Entra app client_secret in Vault.
          # Returns true on success, false if Vault is unavailable.
          def self.store_client_secret(worker_id:, client_secret:, entra_app_id: nil)
            return false unless vault_available?

            path = secret_path(worker_id)
            data = { client_secret: client_secret }
            data[:entra_app_id] = entra_app_id if entra_app_id

            Legion::Crypt.write(path, data)
            Legion::Logging.info "[identity:vault] stored Entra credentials for worker=#{worker_id}"
            true
          rescue StandardError => e
            Legion::Logging.error "[identity:vault] failed to store credentials for worker=#{worker_id}: #{e.message}"
            false
          end

          # Read Entra app client_secret from Vault.
          # Returns the secret hash on success, nil if unavailable or not found.
          def self.read_client_secret(worker_id:)
            return nil unless vault_available?

            path = secret_path(worker_id)
            result = Legion::Crypt.read(path)
            result&.dig(:data, :data) || result&.dig(:data)
          rescue StandardError => e
            Legion::Logging.error "[identity:vault] failed to read credentials for worker=#{worker_id}: #{e.message}"
            nil
          end

          # Delete Entra app credentials from Vault (used during worker termination).
          # Returns true on success, false if Vault is unavailable.
          def self.delete_client_secret(worker_id:)
            return false unless vault_available?

            path = secret_path(worker_id)
            Legion::Crypt.delete(path)
            Legion::Logging.info "[identity:vault] deleted Entra credentials for worker=#{worker_id}"
            true
          rescue StandardError => e
            Legion::Logging.error "[identity:vault] failed to delete credentials for worker=#{worker_id}: #{e.message}"
            false
          end

          def self.vault_available?
            defined?(Legion::Crypt) &&
              defined?(Legion::Settings) &&
              Legion::Settings[:crypt][:vault][:connected] == true
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
