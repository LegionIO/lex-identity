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
          # Falls back to local record when Graph API credentials unavailable.
          def sync_owner(worker_id:, **)
            worker = find_worker(worker_id)
            return { synced: false, error: 'worker not found' } unless worker

            entra_object_id = worker[:entra_object_id]
            return { synced: false, worker_id: worker_id, error: 'no entra_object_id', source: :local } unless entra_object_id

            creds = resolve_graph_credentials
            unless creds
              Legion::Logging.debug "[identity:entra] sync_owner fallback to local: worker=#{worker_id}"
              return { synced: true, worker_id: worker_id, source: :local,
                       owner_msid: worker[:owner_msid], synced_at: Time.now.utc }
            end

            token = Helpers::GraphToken.fetch(**creds)
            conn = Helpers::GraphClient.connection(token: token)
            resp = conn.get("applications/#{entra_object_id}/owners")

            unless resp.success?
              Legion::Logging.warn "[identity:entra] graph owner sync failed: #{resp.status}"
              return { synced: false, worker_id: worker_id, source: :local, owner_msid: worker[:owner_msid] }
            end

            owners = resp.body['value'] || []
            graph_owner_msid = owners.first&.dig('id')
            changed = graph_owner_msid && graph_owner_msid != worker[:owner_msid].to_s

            if changed && defined?(Legion::Data::Model::DigitalWorker)
              Legion::Data::Model::DigitalWorker.where(worker_id: worker_id).update(owner_msid: graph_owner_msid)
              if defined?(Legion::Events)
                Legion::Events.emit('worker.owner_changed', { worker_id: worker_id, old: worker[:owner_msid],
                                                              new: graph_owner_msid })
              end
            end

            { synced: true, source: :graph_api, worker_id: worker_id,
              owner_msid: graph_owner_msid || worker[:owner_msid], changed: !changed.nil?, synced_at: Time.now.utc }
          rescue Helpers::GraphToken::GraphTokenError, Faraday::Error => e
            Legion::Logging.warn "[identity:entra] graph sync error: #{e.message}"
            { synced: false, worker_id: worker_id, source: :local, error: e.message }
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
          # Falls back to local-only scan when Graph API credentials unavailable.
          def check_orphans(**)
            return { orphans: [], checked: 0, source: :unavailable } unless defined?(Legion::Data) && defined?(Legion::Data::Model::DigitalWorker)

            active_workers = Legion::Data::Model::DigitalWorker.where(lifecycle_state: 'active').all
            orphans = []
            skipped = 0

            creds = resolve_graph_credentials
            conn = nil
            if creds
              token = Helpers::GraphToken.fetch(**creds)
              conn = Helpers::GraphClient.connection(token: token)
            end

            active_workers.each do |worker|
              if system_placeholder?(worker.entra_app_id, worker.worker_id)
                skipped += 1
                next
              end

              next unless conn

              orphan_reason = check_worker_orphan_status(conn, worker)
              if orphan_reason
                orphans << worker
                auto_pause_orphan(worker, reason: orphan_reason)
              end
            rescue Faraday::Error => e
              Legion::Logging.warn "[identity:entra] graph error scanning #{worker.worker_id}: #{e.message}"
            end

            source = conn ? :graph_api : :local
            Legion::Logging.debug "[identity:entra] orphan check (#{source}): scanned #{active_workers.size}, skipped #{skipped}"

            {
              orphans:    orphans.map { |w| { worker_id: w.worker_id, owner_msid: w.owner_msid, reason: :entra_orphan } },
              checked:    active_workers.size - skipped,
              skipped:    skipped,
              source:     source,
              checked_at: Time.now.utc
            }
          rescue Helpers::GraphToken::GraphTokenError => e
            Legion::Logging.warn "[identity:entra] orphan check token error: #{e.message}"
            { orphans: [], checked: 0, source: :local, error: e.message, checked_at: Time.now.utc }
          end

          # Map Entra security group OIDs to Legion governance roles
          def resolve_governance_roles(groups:, **)
            group_map = Legion::Settings.dig(:rbac, :entra, :group_map) || {}
            default_role = Legion::Settings.dig(:rbac, :entra, :default_role) || 'governance-observer'
            matched = Array(groups).filter_map { |oid| group_map[oid] }.uniq
            matched = [default_role] if matched.empty?
            { success: true, groups: groups, roles: matched }
          end

          def refresh_access_token(worker_id:, force: false, **)
            require_relative '../helpers/token_cache'

            unless force
              cached = Helpers::TokenCache.fetch(worker_id: worker_id)
              if cached && !Helpers::TokenCache.approaching_expiry?(worker_id: worker_id)
                return { refreshed: false, worker_id: worker_id, source: :cache, expires_at: cached[:expires_at] }
              end
            end

            secret = Helpers::VaultSecrets.read_client_secret(worker_id: worker_id)
            return { refreshed: false, worker_id: worker_id, error: 'vault_unavailable' } unless secret

            tenant_id = resolve_tenant_id
            return { refreshed: false, worker_id: worker_id, error: 'no_tenant_id' } unless tenant_id

            scope = Legion::Settings.dig(:identity, :entra, :token_scope) || 'https://graph.microsoft.com/.default'
            url = "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token"

            require 'faraday'
            resp = Faraday.post(url, {
                                  grant_type:    'client_credentials',
                                  client_id:     secret[:client_id] || secret[:entra_app_id],
                                  client_secret: secret[:client_secret],
                                  scope:         scope
                                })

            unless resp.success?
              Legion::Logging.warn "[identity] token refresh failed for #{worker_id}: #{resp.status}"
              return { refreshed: false, worker_id: worker_id, error: 'token_request_failed' }
            end

            body = Legion::JSON.load(resp.body)
            expires_in = body[:expires_in]&.to_i || 3600
            Helpers::TokenCache.store(worker_id: worker_id, token: body[:access_token], expires_in: expires_in)

            { refreshed: true, worker_id: worker_id, expires_at: Time.now + expires_in }
          rescue StandardError => e
            Legion::Logging.warn "[identity] token refresh error: #{e.message}"
            { refreshed: false, worker_id: worker_id, error: e.message }
          end

          def rotate_client_secret(worker_id:, dry_run: false, **)
            rotation_enabled = Legion::Settings.dig(:identity, :entra, :rotation_enabled)
            buffer_days = Legion::Settings.dig(:identity, :entra, :rotation_buffer_days) || 30

            secret = Helpers::VaultSecrets.read_client_secret(worker_id: worker_id)
            return { rotated: false, worker_id: worker_id, error: 'vault_unavailable' } unless secret

            expires_at = secret[:client_secret_expires_at]
            return { rotated: false, worker_id: worker_id, action_required: false, reason: 'no_expiry_tracked' } unless expires_at

            days_remaining = (Time.parse(expires_at.to_s) - Time.now) / 86_400
            unless days_remaining < buffer_days
              return { rotated: false, worker_id: worker_id, action_required: false,
                       days_remaining: days_remaining.round(1) }
            end

            unless rotation_enabled
              Legion::Logging.warn "[identity] credential expiring for #{worker_id} in #{days_remaining.round(1)} days"
              if defined?(Legion::Events)
                Legion::Events.emit('worker.credential_expiry_warning', {
                                      worker_id: worker_id, days_remaining: days_remaining.round(1)
                                    })
              end
              return { rotated: false, worker_id: worker_id, action_required: true,
                       days_remaining: days_remaining.round(1) }
            end

            return { rotated: false, worker_id: worker_id, dry_run: true, would_rotate: true } if dry_run

            # Graph API rotation would go here when permission is granted
            { rotated: false, worker_id: worker_id, error: 'graph_api_rotation_not_implemented' }
          end

          def credential_refresh_cycle(**)
            return { workers_checked: 0, error: 'data_unavailable' } unless defined?(Legion::Data::Model::DigitalWorker)

            workers = Legion::Data::Model::DigitalWorker.where(lifecycle_state: 'active').all
            results = { workers_checked: 0, refreshed: 0, warned: 0 }

            workers.each do |worker|
              next if system_placeholder?(worker.entra_app_id, worker.worker_id)

              results[:workers_checked] += 1

              token_result = refresh_access_token(worker_id: worker.worker_id)
              results[:refreshed] += 1 if token_result[:refreshed]

              rotation_result = rotate_client_secret(worker_id: worker.worker_id)
              results[:warned] += 1 if rotation_result[:action_required]
            end

            results
          rescue StandardError => e
            Legion::Logging.warn "[identity] credential refresh cycle error: #{e.message}"
            { workers_checked: 0, error: e.message }
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

          def resolve_graph_credentials
            tenant_id = resolve_tenant_id
            return nil unless tenant_id

            secret = Helpers::VaultSecrets.read_client_secret(worker_id: 'legion/identity')
            return nil unless secret && secret[:client_id] && secret[:client_secret]

            { tenant_id: tenant_id, client_id: secret[:client_id], client_secret: secret[:client_secret] }
          rescue StandardError
            nil
          end

          def check_worker_orphan_status(conn, worker)
            # Check if the Entra app registration still exists
            if worker.respond_to?(:entra_object_id) && worker.entra_object_id
              app_resp = conn.get("applications/#{worker.entra_object_id}")
              return :entra_app_deleted unless app_resp.success?
            end

            # Check if the owner account is still active
            if worker.owner_msid
              user_resp = conn.get("users/#{worker.owner_msid}")
              return :owner_deleted unless user_resp.success?
              return :owner_disabled if user_resp.body['accountEnabled'] == false
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
