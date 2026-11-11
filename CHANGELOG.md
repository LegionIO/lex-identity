# Changelog

## [0.3.0] - 2026-11-09

### Added
- Explicit provider-neutral browser login combining PKCE, authorization, a state-correlated loopback callback, and token exchange.
- A single-use callback listener with bounded reads/writes, request limits, optional fixed-port binding, and cleanup on every exit.
- Callback security and lifecycle specs for invalid state, ambiguous parameters, provider denial, stalled clients, timeout, and listener disposal.

### Changed
- Moved reusable OAuth runners to `runners/base/oauth.rb` so generic endpoint and browser operations are not automatically exposed through extension API routes. Consumers must explicitly require the new path.

## [0.2.0] - 2026-11-07

### Added
- Provider integration helpers for resolver registration, lease construction, and broker credential access using one provider name.
- Optional PKCE generation and browser helpers.
- Provider-neutral OAuth authorization, code exchange, refresh, and deadline-bounded device-code polling.
- Reusable provider conformance examples covering the core resolver's metadata and resolution contracts.
- Shared OAuth runner compatible with standard extension discovery; the base extension is not itself an identity provider or remotely invocable.

## [0.1.0] - 2026-11-07

### Added
- Initial gem packaging, namespace, and version.
- Standard actors, runners, helpers, and spec directories.
- Shared CI/release workflow, dependency updates, and RuboCop/RSpec configuration.
