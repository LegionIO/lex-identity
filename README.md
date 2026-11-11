# lex-identity

Shared base extension for LegionIO identity providers. Ruby 3.4+.

Providers opt into small helper mixins and common OAuth runners. No provider
inheritance hierarchy, authentication policy, storage backend, or name-normalization
rule is imposed. Existing identity extensions are not migrated by this gem.

## Layout and runtime ownership

- `lib/legion/extensions/identity/helpers/` — provider integration, PKCE, browser, OAuth, loopback callback listener
- `lib/legion/extensions/identity/runners/base/oauth.rb` — reusable OAuth operations, outside automatic runner discovery
- `lib/legion/extensions/identity/actors/` — reserved for shared actors; no timers are started
- `spec/support/provider_contract.rb` — reusable conformance examples, included in the gem

The base extension reports `identity_provider?`, `remote_invocable?`,
`transport_required?`, and `crypt_required?` as false. It does not register itself
as an identity provider. Shared runner code lives under `runners/base/` and is
explicitly required; only direct `runners/*.rb` files are discovered by LegionIO.
This prevents generic endpoint arguments and browser control from becoming API
routes. `remote_invocable?` alone does not disable route registration.

`Legion::Identity::Resolver`, `Broker`, `Lease`, and `LeaseRenewer` remain owned by
LegionIO core. This gem does not duplicate their registries or renewal scheduler,
and can be loaded without booting LegionIO.

## Provider integration

```ruby
require 'legion/extensions/identity'

# MyProvider is your existing identity provider module or object.
MyProvider.extend(Legion::Extensions::Identity::Helpers::Provider)
MyProvider.identity_register

lease = MyProvider.identity_build_lease(
  credential: access_token,
  expires_at: expires_at,
  renewable: true,
  metadata: { scopes: granted_scopes }
)
MyProvider.identity_register_credential(lease: lease, qualifier: :work, default: true)
MyProvider.identity_credentials_available
MyProvider.identity_token_for(qualifier: :work, purpose: :api_request)
```

All registration, lease provenance, credential discovery, and token lookup use
`MyProvider.provider_name`. There is no second provider-name argument to keep in sync.

| Method | Behavior |
|---|---|
| `identity_register` | Registers with the loaded Resolver, or appends to core's existing pending registrations; returns `:registered`, `:pending`, or `:unavailable` when core is absent. Standalone loading does not raise or create a second registry. |
| `identity_build_lease(credential:, **attributes)` | Builds the core Lease when loaded, otherwise a plain attribute Hash for standalone use. The provider name cannot be overridden through attributes. |
| `identity_register_credential(lease:, qualifier: :default, default: false)` | Registers with core Broker; raises if Broker is unavailable. Pass a real core Lease when using Broker. |
| `identity_credentials_available` | Returns this provider's broker qualifiers, or `[]` before Broker loads. |
| `identity_token_for(qualifier: nil, **options)` | Uses Broker lookup, including context/purpose options; returns `nil` before Broker loads. |

Providers retain their metadata: `provider_name`, `provider_type`, `priority`,
`trust_weight`, `trust_level`, and `capabilities`. They also retain subject
verification, profile mapping, normalization, and credential acquisition.

## Optional browser and PKCE helpers

```ruby
require 'legion/extensions/identity/helpers/pkce'
require 'legion/extensions/identity/helpers/browser'

helper = Object.new
helper.extend(Legion::Extensions::Identity::Helpers::Pkce)
helper.extend(Legion::Extensions::Identity::Helpers::Browser)

proof = helper.pkce_generate
# { code_verifier:, code_challenge:, code_challenge_method: 'S256' }
helper.browser_open(url: authorization_url) if helper.browser_gui_available?
```

These low-level browser/PKCE helpers do not start login sessions. The optional
`browser_login` runner below supplies the common callback lifecycle.

## Optional OAuth operations

```ruby
require 'legion/extensions/identity/runners/base/oauth'

oauth = Legion::Extensions::Identity::Runners::Oauth
url = oauth.oauth_authorize_url(
  authorization_endpoint: authorization_endpoint,
  client_id: client_id,
  redirect_uri: redirect_uri,
  scope: 'openid profile',
  state: state,
  code_challenge: proof[:code_challenge]
)

result = oauth.exchange_code(
  token_endpoint: token_endpoint,
  client_id: client_id,
  code: code,
  redirect_uri: redirect_uri,
  code_verifier: proof[:code_verifier]
)
```

The authorization URL helper returns a String, preserving unrelated endpoint query
parameters while replacing conflicting OAuth parameters. Scope values are
space-separated strings.

The public runners return `{ result: provider_response }` on success or
`{ error:, description: }` on failure:

- `browser_login(authorization_endpoint:, token_endpoint:, client_id:, scope:, callback_port: 0, callback_timeout: 120)`

- `request_device_code(device_authorization_endpoint:, client_id:, scope:)`
- `exchange_code(token_endpoint:, client_id:, code:, redirect_uri:, code_verifier:, scope: nil)`
- `refresh_token(token_endpoint:, client_id:, refresh_token:, scope: nil)`
- `poll_device_code(token_endpoint:, client_id:, device_code:, interval: 5, timeout: 300)`

Device responses require a nonempty device code; token responses require a
nonempty access token. Provider errors are preserved rather than wrapped as success.
Polling uses monotonic time, increases the wait by five seconds on `slow_down`,
and caps waits and request timeouts by the remaining budget. A zero timeout does
not send a request; nonpositive intervals and negative timeouts raise `ArgumentError`.

For provider-specific runners, extend the helpers you use and the common runner:

```ruby
MyRunner.extend(Legion::Extensions::Identity::Helpers::Oauth)
MyRunner.extend(Legion::Extensions::Identity::Helpers::Pkce)    # browser_login
MyRunner.extend(Legion::Extensions::Identity::Helpers::Browser) # browser_login
MyRunner.extend(Legion::Extensions::Identity::Runners::Oauth)
```

`Helpers::Oauth#oauth_post(endpoint:, form:, open_timeout: 5, request_timeout: 15)`
provides form encoding and symbol-keyed JSON parsing for additional provider grants.
It propagates transport exceptions; the public runners log and return an explicit
failure. No token persistence, refresh-token rotation policy, or scheduled refresh
is implemented here.

Concrete provider runners can expose provider-specific operations using configured
endpoints. Do not expose these generic endpoint arguments through a public runner.
The old `legion/extensions/identity/runners/oauth` require path has been removed;
use the explicit `runners/base/oauth` path.

## Explicit browser login

```ruby
require 'legion/extensions/identity/runners/base/oauth'

result = Legion::Extensions::Identity::Runners::Oauth.browser_login(
  authorization_endpoint: authorization_endpoint,
  token_endpoint: token_endpoint,
  client_id: client_id,
  scope: 'openid profile',
  callback_port: 0,
  callback_timeout: 120
)
```

Each call creates its own state, PKCE verifier, and listener. The runner opens the
browser, waits for a correlated authorization response, exchanges the code using
the exact redirect URI and verifier, then returns the existing token-result Hash.
Providers still own token persistence and authenticated-subject verification.

The redirect URI is `http://127.0.0.1:<port>/callback`. Port `0` requests an available
ephemeral port. If your provider requires an exact registered redirect URI, supply
its registered fixed port; the listener never binds a non-loopback interface.

The listener accepts only a complete GET callback with matching state and exactly
one nonempty code or error. Missing/mismatched state, duplicate parameters,
ambiguous code/error responses, and malformed requests are rejected without
consuming the pending login. Unrelated paths do not terminate the wait. State is
checked before accepting provider errors as well as authorization codes.

Callback waiting uses a monotonic deadline, with an 8 KiB header limit and a
two-second per-client I/O budget bounded by the remaining wait. The listener and
accepted sockets close on success, provider denial, timeout, and exceptions.
Browser-launch failure also closes the listener. The static browser response
contains no callback parameters and only confirms receipt—not token-exchange
success.

`callback_timeout` must be positive and finite. It bounds callback waiting, not
browser process startup or the subsequent token endpoint's separate HTTP timeouts.
A missing graphical session returns `browser_unavailable`; launcher failure returns
`browser_launch_failed`; an unanswered callback returns `timeout`.

This is explicit user-initiated login only. There is no automatic sign-in, persistent
session store, background actor, API-hook registration, or implicit device-code
fallback. Headless callers can use `request_device_code` and `poll_device_code`.

## Shared provider conformance

```ruby
require File.join(
  Gem.loaded_specs.fetch('lex-identity').full_gem_path,
  'spec/support/provider_contract'
)

RSpec.describe MyProvider do
  let(:identity_provider) { described_class }
  let(:canonical_name) { 'example-user' }

  # Configure your provider's upstream responses in the surrounding spec.
  it_behaves_like 'identity provider contract'
end
```

These examples exercise the current core resolver contract:

- Auth and fallback providers receive `resolve` without arguments.
- Profile providers receive `resolve_all(canonical_name:)` when present, otherwise
  `resolve(canonical_name:)`. The selected method must return a profile Hash or
  `nil`, not an account Array.
- Auth/fallback results require a valid canonical name, kind, and source.
- Profile providers cannot choose the canonical name.
- Metadata types and trust levels are checked without forcing common values.

Account enumeration is separate from the profile result consumed by core. The
shared examples do not add or change a provider's `resolve_all` implementation.

## Development

```bash
bundle install
bundle exec rspec --format json --out tmp/rspec_results.json --format progress --out tmp/rspec_progress.txt
bundle exec rubocop -A
```

## License

MIT.
