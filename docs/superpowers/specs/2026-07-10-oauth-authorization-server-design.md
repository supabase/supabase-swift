# OAuth 2.1 Authorization Server (consent/grants) support

Linear: [SDK-1295](https://linear.app/supabase/issue/SDK-1295/auth-oauth-20-authorization-server-support)

## Problem

Supabase Auth can act as its own OAuth 2.1 authorization server for third-party
client apps. When a third-party app requests access, the *end user* (a user of
the app built on Supabase, signed in via our SDK) needs to see a consent
screen and approve/deny it, and later be able to see and revoke apps they've
granted access to. supabase-swift has no client support for any of this today.

This is distinct from two features that already exist:
- `signInWithOAuth` / `linkIdentity` — the app's user signing in *via* a
  third-party OAuth provider (Google, GitHub, ...). Not touched by this work.
- `AuthAdmin.oauth` (`AuthAdminOAuth`) — admin/server-side CRUD for
  *registering* OAuth client apps against the project. Already implemented.
  Not touched by this work.

Reference implementation: supabase-js `auth-js`, `GoTrueClient.ts`
(`oauth: AuthOAuthServerApi`, introduced in PRs #1793 and #1833). Backend:
`supabase/auth` (Go), `internal/api/oauthserver/`.

## API design

New struct `AuthOAuthServer`, exposed as `AuthClient.oauthServer` (nested
namespace pattern used by `AuthMFA`/`mfa` and `AuthAdmin`/`admin`). Named
`oauthServer` rather than mirroring JS's `oauth` 1:1 to avoid a naming
collision with the unrelated `admin.oauth` (OAuth *client* CRUD) — same leaf
name at a different nesting depth would be an ambiguity trap.

```swift
public struct AuthOAuthServer: Sendable {
  public func getAuthorizationDetails(authorizationId: String) async throws -> OAuthAuthorizationDetailsResponse
  public func approveAuthorization(authorizationId: String) async throws -> OAuthRedirect
  public func denyAuthorization(authorizationId: String) async throws -> OAuthRedirect
  public func listGrants() async throws -> [OAuthGrant]
  public func revokeGrant(clientId: UUID) async throws
}
```

Deliberate deviations from JS:
- No `skipBrowserRedirect` option on approve/deny — that flag exists in JS to
  suppress an automatic `window.location.assign`, which has no Swift
  equivalent. The Swift methods just return the `URL`; the caller decides how
  to present it (`ASWebAuthenticationSession`, `SFSafariViewController`, etc).
- `getAuthorizationDetails` returns an enum, not a TS union type, because the
  backend can silently auto-approve: if the user already has an active
  consent covering the requested scopes for that client, the GET handler
  approves in-place and returns `{redirect_url}` instead of the documented
  details shape. This is real backend behavior (confirmed by reading
  `internal/api/oauthserver/authorize.go`), not in the OpenAPI spec at all.
- `denyAuthorization` does not throw. The backend returns HTTP 200 with an
  `access_denied` OAuth error embedded in the redirect URL's query string
  (RFC 6749 behavior) — denial is a successful API call, matching JS.
- `revokeGrant(clientId: UUID)` takes a plain labeled parameter instead of an
  options struct (JS: `revokeGrant(options: { clientId })`) — Swift doesn't
  need a wrapper type for one field.

All five methods are session-bound (call `api.authorizedExecute`, which
throws `AuthError.sessionMissing` automatically if there's no active session
— same as `AuthMFA`).

### Endpoints

| Method | Swift call | HTTP |
|---|---|---|
| `getAuthorizationDetails` | GET | `/oauth/authorizations/{authorizationId}` |
| `approveAuthorization` | POST | `/oauth/authorizations/{authorizationId}/consent` body `{"action":"approve"}` |
| `denyAuthorization` | POST | `/oauth/authorizations/{authorizationId}/consent` body `{"action":"deny"}` |
| `listGrants` | GET | `/user/oauth/grants` |
| `revokeGrant` | DELETE | `/user/oauth/grants?client_id={uuid}` → 204, no body decoded (same pattern as `AuthAdmin.deleteUser`) |

Known discrepancies between `supabase/auth`'s `openapi.yaml` and actual code
(confirmed by reading `internal/api/oauthserver/{authorize.go,handlers.go}`
and `internal/models/oauth_authorization.go`), which the implementation must
follow the *code* for for, not the spec:

1. GET `/oauth/authorizations/{id}` can return either the documented details
   object or a bare `{"redirect_url": ...}` (auto-approve short-circuit).
2. Approving persists a durable `oauth_consents` row (future authorize calls
   for the same client/scopes auto-approve) — not mentioned in the spec.
3. Both authorization endpoints can additionally 403 `bad_jwt` (defensive,
   effectively unreachable) or 404 with error code `feature_disabled` when
   `GOTRUE_OAUTH_SERVER_ENABLED` is off — neither is in the spec's per-path
   error tables.
4. A different user owning the authorization is deliberately mapped to 404
   `oauth_authorization_not_found`, not 401/403 (avoid leaking existence).
5. Expired-but-still-`pending` authorizations get lazily flipped to
   `status='expired'` on the next GET/consent call before the 404 fires.
6. DELETE `/user/oauth/grants` 400s on a non-UUID `client_id` too (error code
   `validation_failed`), not just a missing one.

### Types (new, in `Types.swift`)

```swift
public struct OAuthAuthorizationClient: Codable, Hashable, Sendable {
  public let id: UUID
  public let name: String
  public let uri: URL?
  public let logoUri: URL?
}

public struct OAuthAuthorizationUser: Codable, Hashable, Sendable {
  public let id: UUID
  public let email: String
}

public struct OAuthAuthorizationDetails: Codable, Hashable, Sendable {
  public let authorizationId: String
  public let redirectUri: URL
  public let client: OAuthAuthorizationClient
  public let user: OAuthAuthorizationUser
  public let scope: String
}

public struct OAuthRedirect: Codable, Hashable, Sendable {
  public let redirectURL: URL  // JSON key "redirect_url"
}

public enum OAuthAuthorizationDetailsResponse: Sendable, Hashable {
  case details(OAuthAuthorizationDetails)
  case redirect(OAuthRedirect)
}

public struct OAuthGrant: Codable, Hashable, Sendable {
  public let client: OAuthAuthorizationClient
  public let scopes: [String]
  public let grantedAt: Date
}
```

Field types verified against actual Go structs, not the spec:
- `authorizationId: String` — confirmed NOT a UUID. Generated by
  `crypto.SecureAlphanumeric(32)` (`internal/models/oauth_authorization.go:86`),
  a 32-char lowercase base32 token, distinct from the internal `id uuid`
  column (`json:"-"`, never serialized).
- `OAuthAuthorizationClient.id: UUID` — maps to `oauth_clients.id` (uuid
  column), consistent with the existing `OAuthClient.clientId: UUID` in the
  admin API.
- `uri`/`logoUri: URL?` — Go's `ClientDetailsResponse.URI`/`LogoURI` are
  plain (non-pointer) strings tagged `,omitempty`
  (`internal/api/oauthserver/authorize.go:45-51`), so an empty value is an
  *absent key*, not an empty string — safe for a plain `URL?` Decodable,
  no custom empty-string handling needed.

`OAuthAuthorizationDetailsResponse` needs custom `Decodable`: try decoding
`OAuthAuthorizationDetails` first (requires the `authorization_id` key);
on failure, decode `OAuthRedirect`.

### Errors

New `ErrorCode` entries in `AuthError.swift`: `oauthAuthorizationNotFound`
(`oauth_authorization_not_found`), `oauthConsentNotFound`
(`oauth_consent_not_found`), `featureDisabled` (`feature_disabled`). No new
`AuthError` cases — the existing generic `.api(message:errorCode:...)` case
covers all of these, same as every other Auth error.

## Testing

**Unit tests** (`Tests/AuthTests/AuthOAuthServerTests.swift`, XCTest +
Mocker, mirroring `AuthAdminOAuthTests.swift`):
- Each of the 5 methods: happy path, request shape (URL, method, body/query).
- `getAuthorizationDetails`: both response shapes (full details, and the
  auto-approve redirect-only shape).
- Error cases: 404 `oauth_authorization_not_found`, 400 `validation_failed`
  (not-pending / bad client_id), `AuthError.sessionMissing` when no session.

**Integration tests**: add `[auth.oauth_server]` (enabled) to
`Tests/IntegrationTests/supabase/config.toml`. Seed a fixture via the
already-implemented `admin.oauth.createClient(...)`. Since seeding a
*pending* authorization requires hitting `GET /oauth/authorize` — deliberately
outside this SDK's surface, same as the JS port — do one raw `URLSession`
call (custom `URLSessionTaskDelegate` that suppresses redirect-following) to
extract `authorization_id` from the 302 `Location` header, then exercise
`getAuthorizationDetails` → `approveAuthorization`/`denyAuthorization` →
`listGrants` → `revokeGrant` through the real SDK methods.

## Out of scope

- `/oauth/authorize` and `/oauth/token` (third-party client integration) —
  explicitly out of scope in the JS port too.
- `AuthAdmin.oauth` OAuth-client CRUD — already implemented.
