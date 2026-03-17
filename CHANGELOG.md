# Changelog

## [0.4.0] - 2026-03-17

### Added
- `Helpers::GraphClient`: Faraday connection builder for Microsoft Graph API with bearer auth
- `Helpers::GraphToken`: client-credentials token acquisition from Entra for Graph API calls
- `sync_owner` now calls Graph API `/applications/{id}/owners` for real owner data (falls back to local)
- `check_orphans` now detects deleted apps and disabled owners via Graph API (falls back to local)
- `resolve_governance_roles(groups:)`: maps Entra security group OIDs to Legion governance roles via settings
- Private `resolve_graph_credentials` and `check_worker_orphan_status` helpers

## [0.3.0] - 2026-03-17

### Added
- `Helpers::TokenCache`: thread-safe in-memory OAuth access_token store with expiry tracking
- `refresh_access_token(worker_id:)`: acquires client_credentials token from Entra, caches result
- `rotate_client_secret(worker_id:)`: detects approaching credential expiry, emits warning event
- `credential_refresh_cycle`: batch refresh/rotation check for all active workers
- `CredentialRefresh` actor: runs every 6 hours

## [0.2.0] - 2026-03-16

### Added
- `validate_worker_identity` now performs cryptographic OIDC token validation via Entra JWKS endpoint when token is provided
- Entra JWKS URL and issuer templates for tenant-specific validation
- Token error handling: expired, invalid signature, and generic errors return structured results
- `resolve_tenant_id` helper for reading tenant from settings
- `spec/legion/extensions/identity/actors/orphan_check_spec.rb` (12 examples) — tests for the OrphanCheck actor (Every 14400s)

## [0.1.0] - 2026-03-13

### Added
- Initial release
