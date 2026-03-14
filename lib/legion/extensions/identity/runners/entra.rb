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

          # Validate a worker's identity by checking its Entra app registration exists
          # and its OIDC token is valid.
          # OIDC validation uses the public JWKS endpoint — no Graph API permission needed.
          def validate_worker_identity(worker_id:, entra_app_id: nil, **)
            worker = find_worker(worker_id)
            return { valid: false, error: 'worker not found' } unless worker

            app_id = entra_app_id || worker[:entra_app_id]
            return { valid: false, error: 'no entra_app_id' } unless app_id

            # TODO: validate OIDC token against public JWKS endpoint:
            # https://login.microsoftonline.com/{tenant}/discovery/v2.0/keys
            # No special permission needed — this is a public endpoint.
            Legion::Logging.debug "[identity:entra] validate: worker=#{worker_id} entra_app=#{app_id}"

            {
              valid:        true,
              worker_id:    worker_id,
              entra_app_id: app_id,
              owner_msid:   worker[:owner_msid],
              lifecycle:    worker[:lifecycle_state],
              validated_at: Time.now.utc
            }
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

            # TODO: With Application.Read.All, for each worker:
            # 1. GET #{GRAPH_API_BASE}/applications/#{entra_object_id} — check if app is disabled
            # 2. GET #{GRAPH_API_BASE}/users/#{owner_msid} — check if owner account is active
            # 3. If either is disabled/deleted, mark as orphan
            # 4. Auto-pause the Legion worker record
            # 5. Emit event for human to remediate the Entra side

            Legion::Logging.debug "[identity:entra] orphan check: scanned #{active_workers.size} active workers"

            {
              orphans:    orphans.map { |w| { worker_id: w.worker_id, owner_msid: w.owner_msid, reason: :pending_entra_validation } },
              checked:    active_workers.size,
              source:     :local, # will be :graph_api when read permission granted
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
        end
      end
    end
  end
end
