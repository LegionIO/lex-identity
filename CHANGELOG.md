# Changelog

## [Unreleased]

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
