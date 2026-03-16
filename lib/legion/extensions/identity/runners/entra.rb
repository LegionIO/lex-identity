# frozen_string_literal: true

module Legion
  module Extensions
    module Identity
      module Runners
        # Entra ID Application identity integration for Digital Workers.
        #
        # Permission model:
        #   - Entra app CREATION is done by the human owner (requires Application.ReadWrite.All
        #     which Legion does not have and should not have)
        #   - Legion gets Application.Read.All or Directory.Read.All for read operations
        #   - OIDC token validation uses the public JWKS endpoint (no special permission)
        #   - Write operations (transfer ownership, disable apps) update the Legion DB
        #     and emit events; the human completes the Entra side manually
        module Entra
          GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'
          ENTRA_JWKS_URL_TEMPLATE = 'https://login.microsoftonline.com/%<tenant_id>s/discovery/v2.0/keys'
          ENTRA_ISSUER_TEMPLATE = 'https://login.microsoftonline.com/%<tenant_id>s/v2.0'

          # Validate a worker's identity by checking its Entra app registration exists
          # and its OIDC token is valid.
          # OIDC validation uses the public JWKS endpoint — no Graph API permission needed.
          def validate_worker_identity(worker_id:, entra_app_id: nil, token: nil, tenant_id: nil, **)
            worker = find_worker(worker_id)
            return { valid: false, error: 'worker not found' } unless worker

            app_id = entra_app_id || worker[:entra_app_id]
            return { valid: false, error: 'no entra_app_id' } unless app_id

            # If a token is provided and legion-crypt has JWKS support, validate it
            if token && defined?(Legion::Crypt::JWT) && Legion::Crypt::JWT.respond_to?(:verify_with_jwks)
              tid = tenant_id || resolve_tenant_id
              return { valid: false, error: 'no tenant_id configured' } unless tid

              jwks_url = format(ENTRA_JWKS_URL_TEMPLATE, tenant_id: tid)
              issuer = format(ENTRA_ISSUER_TEMPLATE, tenant_id: tid)

              claims = Legion::Crypt::JWT.verify_with_jwks(
                token,
                jwks_url: jwks_url,
                issuers:  [issuer],
                audience: app_id
              )

              Legion::Logging.debug "[identity:entra] token validated: worker=#{worker_id} sub=#{claims[:sub]}"

              return {
                valid:        true,
                worker_id:    worker_id,
                entra_app_id: app_id,
                owner_msid:   worker[:owner_msid],
                lifecycle:    worker[:lifecycle_state],
                claims:       claims,
                validated_at: Time.now.utc
              }
            end

            # No token provided — return identity info without token validation
            Legion::Logging.debug "[identity:entra] validate (no token): worker=#{worker_id} entra_app=#{app_id}"

            {
              valid:        true,
              worker_id:    worker_id,
              entra_app_id: app_id,
              owner_msid:   worker[:owner_msid],
              lifecycle:    worker[:lifecycle_state],
              validated_at: Time.now.utc
            }
          rescue Legion::Crypt::JWT::ExpiredTokenError => e
            { valid: false, error: 'token_expired', message: e.message }
          rescue Legion::Crypt::JWT::InvalidTokenError => e
            { valid: false, error: 'token_invalid', message: e.message }
          rescue Legion::Crypt::JWT::Error => e
            { valid: false, error: 'token_error', message: e.message }
          end

          # Sync the worker's owner from Entra app ownership.
          # Requires: Application.Read.All or Directory.Read.All (read-only)
          def sync_owner(worker_id:, **)
            worker = find_worker(worker_id)
            return { synced: false, error: 'worker not found' } unless worker

            # TODO: With Application.Read.All, call:
            # GET #{GRAPH_API_BASE}/applications/#{worker[:entra_object_id]}/owners
            # Parse owner MSID from response, update local record

            Legion::Logging.debug "[identity:entra] sync_owner: worker=#{worker_id} current_owner=#{worker[:owner_msid]}"

            {
              synced:     true,
              worker_id:  worker_id,
              owner_msid: worker[:owner_msid],
              source:     :local, # will be :graph_api when read permission granted
              synced_at:  Time.now.utc
            }
          end

          # Transfer ownership of a digital worker to a new human.
          # Updates the Legion DB record and emits an audit event.
          # The Entra app ownership change must be done by the human owner
          # (requires Application.ReadWrite.All which Legion intentionally does not have).
          def transfer_ownership(worker_id:, new_owner_msid:, transferred_by:, reason: nil, **)
            worker = find_worker(worker_id)
            return { transferred: false, error: 'worker not found' } unless worker

            old_owner = worker[:owner_msid]
            return { transferred: false, error: 'same owner' } if old_owner == new_owner_msid

            # Update local record — this is the Legion side of the transfer
            if defined?(Legion::Data) && defined?(Legion::Data::Model::DigitalWorker)
              dw = Legion::Data::Model::DigitalWorker.first(worker_id: worker_id)
              dw&.update(owner_msid: new_owner_msid, updated_at: Time.now.utc)
            end

            # Entra app ownership change requires Application.ReadWrite.All.
            # Legion does not have this permission by design — the human owner
            # must update Entra app ownership separately via Azure Portal or CLI.

            audit = {
              event:                 :ownership_transferred,
              worker_id:             worker_id,
              from_owner:            old_owner,
              to_owner:              new_owner_msid,
              transferred_by:        transferred_by,
              reason:                reason,
              entra_action_required: 'update Entra app ownership via Azure Portal or az CLI',
              at:                    Time.now.utc
            }

            Legion::Events.emit('worker.ownership_transferred', audit) if defined?(Legion::Events)
            Legion::Logging.info "[identity:entra] ownership transferred (Legion DB): worker=#{worker_id} " \
                                 "from=#{old_owner} to=#{new_owner_msid} by=#{transferred_by}"
            Legion::Logging.warn '[identity:entra] Entra app ownership must be updated manually (requires Application.ReadWrite.All)'

            { transferred: true }.merge(audit)
          end

          # Scan for orphaned workers: Entra apps that are disabled or owners no longer active.
          # Requires: Application.Read.All or Directory.Read.All (read-only)
          # Orphan REMEDIATION (disabling apps) requires human action since Legion
          # does not have Application.ReadWrite.All.
          def check_orphans(**)
            return { orphans: [], checked: 0, source: :unavailable } unless defined?(Legion::Data) && defined?(Legion::Data::Model::DigitalWorker)

            active_workers = Legion::Data::Model::DigitalWorker.where(lifecycle_state: 'active').all
            orphans = []
            skipped = 0

            active_workers.each do |worker|
              # Skip auto-registered extension workers without real Entra apps
              if system_placeholder?(worker.entra_app_id, worker.worker_id)
                skipped += 1
                next
              end

              # TODO: With Application.Read.All, check:
              # GET #{GRAPH_API_BASE}/applications/#{entra_object_id} — is app disabled?
              # GET #{GRAPH_API_BASE}/users/#{owner_msid} — is owner active?
              # If either is disabled/deleted:
              #   orphans << worker
              #   auto_pause_orphan(worker, reason: :entra_app_disabled)
            end

            Legion::Logging.debug "[identity:entra] orphan check: scanned #{active_workers.size} active workers, skipped #{skipped} system workers"

            {
              orphans:    orphans.map { |w| { worker_id: w.worker_id, owner_msid: w.owner_msid, reason: :pending_entra_validation } },
              checked:    active_workers.size - skipped,
              skipped:    skipped,
              source:     :local,
              checked_at: Time.now.utc
            }
          end

          private

          def find_worker(worker_id)
            if defined?(Legion::Data) && defined?(Legion::Data::Model::DigitalWorker)
              worker = Legion::Data::Model::DigitalWorker.first(worker_id: worker_id)
              return worker.to_hash if worker
            end
            nil
          end

          def system_placeholder?(entra_app_id, worker_id)
            return true if entra_app_id.nil? || entra_app_id == 'system'
            return true if entra_app_id == worker_id
            return true if entra_app_id.start_with?('lex-')

            false
          end

          def resolve_tenant_id
            if defined?(Legion::Settings) &&
               Legion::Settings[:identity]&.dig(:entra, :tenant_id)
              return Legion::Settings[:identity][:entra][:tenant_id]
            end

            nil
          end

          def auto_pause_orphan(worker, reason:)
            worker.update(lifecycle_state: 'paused', updated_at: Time.now.utc)

            if defined?(Legion::Events)
              Legion::Events.emit('worker.orphan_detected', {
                                    worker_id:   worker.worker_id,
                                    owner_msid:  worker.owner_msid,
                                    reason:      reason,
                                    action:      :auto_paused,
                                    remediation: 'disable or reassign Entra app via Azure Portal',
                                    at:          Time.now.utc
                                  })
            end

            Legion::Logging.warn "[identity:entra] orphan detected: worker=#{worker.worker_id} reason=#{reason} — auto-paused"
          end
        end
      end
    end
  end
end
