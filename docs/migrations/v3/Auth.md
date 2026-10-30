# Auth v3 migration

This file covers the changes to `AuthClient`, sessions, MFA, OAuth, `AuthError` and local storage
from v2 to v3. See [the v3 migration overview](../../../V3_MIGRATION.md) for steps that apply to
every module.

> [!NOTE]
> The Auth API is still being reworked for v3. It may change before v3.0.0.

## Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **Initial session can be expired.** `.initialSession` now fires at once with the stored session.
  With `autoRefresh: .automatic`, auto refresh then refreshes an expired session as soon as it
  runs. On macOS, Linux, Android, and Windows, it runs when the client is created. On iOS, iPadOS,
  tvOS, visionOS, Mac Catalyst, and watchOS, it runs only while the app is in the foreground. After
  a launch into the background, the session stays expired until the app comes to the foreground or
  a read of `session` refreshes it. Check `session.isExpired` in handlers that switch on
  `.initialSession`.
- **`KeychainLocalStorage` returns `nil` for a missing key.** `retrieve(key:)` no longer throws
  when no item exists, and `remove(key:)` on a missing key does nothing. Remove `catch` blocks that
  treated an error as "no session". A custom `AuthLocalStorage` must follow the same contract.
- **Network and decoding errors are wrapped.** `URLError` and `DecodingError` arrive as
  `AuthError` with kind `.transport` or `.decoding`; the original is in `underlyingError`. A
  cancelled task throws `CancellationError`. Search for `as URLError` and `as DecodingError` near
  Auth calls.
- **Retries.** Auth makes up to 3 attempts instead of 2, with a random (jittered) wait, and
  honors `Retry-After`. A `ClientMiddleware` runs once per attempt.
- **`init(rawValue:)` cannot fail.** On the types that became structs (see the table), it always
  returns a value. `X(rawValue: s) != nil` is now always `true`. Remove that check.
- **String interpolation.** `"\(provider)"` on those structs prints
  `Provider(rawValue: "apple")`, not `apple`. `"\(error)"` on an `AuthError` prints
  `AuthError(server): …`, not the case name. Use `.rawValue` or `.message`.
- **A rejected session has its own kind.** When the server rejects the session or its refresh
  token (`refresh_token_not_found`, `refresh_token_already_used`, `session_expired`,
  `session_not_found`, `user_banned`), the error kind is `.sessionInvalidated`, not
  `.sessionMissing`. `errorCode` and `message` keep the server's values. `.sessionMissing` now
  means only that no session is stored. Search for `.sessionMissing`. To send the user back to
  sign-in, react to the `.signedOut` event (see the next entry on refresh failures).
- **The stored session has a new format.** The first read after the upgrade rewrites the stored
  session in a versioned format with snake_case keys and ISO 8601 dates, and moves a session
  stored under the old `supabase.session` key to the configured key. v2 cannot read the new
  format, so going back to v2 signs users out. Code that reads the session JSON from your
  `AuthLocalStorage` directly must read the new format.
- **Storage errors surface.** When `localStorage` throws while the client saves or removes the
  session, the call that changed the session (a sign-in, `refreshSession`, `signOut`) throws that
  error and the session stays as it was. v2 logged the error and went on. When the read at launch
  throws, `currentSession` is `nil` and `session` throws the storage error, not `.sessionMissing`;
  v2 read a failed read as signed out.
- **A locked Keychain is not signed out.** `KeychainLocalStorage` throws an `AuthError` of kind
  `.storageUnavailable` while the device is locked (`errSecInteractionNotAllowed`), and of kind
  `.storageMisconfigured` when the app lacks the Keychain entitlement (`errSecMissingEntitlement`).
  v2 threw an internal Keychain error, and a launch into the background before the first unlock
  emitted `.initialSession` with no session. Now `.initialSession` waits until storage is read.
  Until then, each call that needs the session reads storage again: `session`,
  `refreshSessionIfNeeded`, a request that sends the session's access token (such as `user()` or a
  `SupabaseClient` data request), and each new `onAuthStateChange` or `authStateChanges`
  subscription. `session` throws `.storageUnavailable` while the device is locked. On iOS, iPadOS,
  tvOS, visionOS, and Mac Catalyst the client also reads storage when protected data becomes
  available. watchOS and macOS post no such notification, so there only those calls read storage
  again. A sign-in that throws `.storageUnavailable` did not sign in, so retry it after the device
  unlocks. The client also reports the first `.storageMisconfigured` error from its storage as a
  runtime issue, whether a read at launch or a later write, such as the save of a sign-in, throws
  it. On macOS with `useDataProtectionKeychain: true` and no entitlement, a read finds no item, so
  the report comes from the first sign-in.
- **Unit tests with the default storage report an issue.** A test bundle with no host app on an
  iOS, tvOS, visionOS, or watchOS simulator has no Keychain entitlement. A test there that creates
  a client with the default `KeychainLocalStorage` now records a runtime issue when it creates the
  client, and Swift Testing and XCTest fail the test. Pass storage that keeps values in memory in
  tests. The SDK's `InMemoryAuthStorage` conforms to `AuthStorage`, not `AuthLocalStorage`, so
  `AuthOptions(storage:)` does not take it. Define your own:

  ```swift
  final class InMemoryLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
  }

  let client = SupabaseClient(
    supabaseURL: url,
    supabaseKey: key,
    options: .init(auth: .init(storage: InMemoryLocalStorage()))
  )
  ```
- **The stored session is read once.** The client reads `localStorage` when it is created and
  keeps the session in memory. `currentSession` no longer reads storage, so a session that other
  code (an app extension, another process) writes to the same storage is not seen until the next
  client is created.
- **Each client keeps its own session in memory.** Because the session is read once, two
  clients with the same storage and storage key do not see each other's changes. When one
  refreshes, the other still holds the old refresh token, and its next refresh fails with
  `refresh_token_already_used`. It signs out on the first such refresh after its session
  expires. Create one client per project, or give each client its own `storageKey`.
- **Refreshes are deduplicated and throttled.** A client runs one refresh of a refresh token at a
  time. A cancelled caller of `session` or `refreshSession` throws `CancellationError` at once,
  and the shared refresh still finishes. When a refresh fails, a new refresh with that same token
  in the next 60 seconds throws the same error without a request. After five refreshes in 30
  seconds, the next one throws an `AuthError` with kind `.excessiveRefresh`. `signOut` cancels a
  running refresh. Its callers get `CancellationError`, whatever error the request then ends
  with, or `.refreshDiscarded` when a successful response arrived first. Search for retry loops
  around `refreshSession`.
- **A rejected refresh does not sign out while the access token is valid.** A refresh that fails
  with a network error, a 5xx, a 408, a 409, or a 429 keeps the session. A refresh that the server
  rejects (`.sessionInvalidated`) signs out only when the access token is expired, as the client
  judges it (see the next entry). When it is not, as for a refresh you start early with
  `refreshSession()`, the session stays and
  `refreshSession()` throws. The first refresh after the session expires signs out. v2 signed out
  at once on `refresh_token_not_found`, `refresh_token_already_used`, `session_expired`, and
  `session_not_found`. v3 also signs out on `user_banned` and on an OAuth `invalid_grant`. Do not
  read a `.sessionInvalidated` error from `refreshSession()` as a sign-out. Wait for the
  `.signedOut` event. A rejected token that is not the current session's, as in
  `refreshSession(refreshToken:)` or `user(jwt:)` with another token or while signed out, never
  signs out and fires no event.
- **Expiry follows the local clock, and auto refresh runs on a deadline.** The client judges
  expiry from the local time it received the session plus `expiresIn`, not from `expiresAt`
  against the device clock. On a device whose clock is wrong, `session` no longer refreshes on
  every call. `Session.isExpired` still compares `expiresAt` with the device clock, so on such a
  device it can disagree with the client. `startAutoRefresh()` no longer checks the session every
  30 seconds. It refreshes once, 90 seconds before the access token expires, and retries a failed
  refresh with a capped exponential backoff. A session stored by v2 counts as received at
  `expiresAt - expiresIn`.
- **Auto refresh starts with the client and follows the app lifecycle.** With
  `autoRefresh: .automatic`, the default, auto refresh starts when the client is created, on
  every platform. v2 waited for the app to become active, and never refreshed on Linux, Android,
  Windows, or in a command-line tool. On iOS, iPadOS, tvOS, visionOS, Mac Catalyst, and watchOS,
  it pauses while the app is in the background, also after a launch into the background, and
  refreshes at once when the app returns to the foreground, if the session is due. v2 paused when the app resigned active, so an alert or
  Control Center paused it too. On macOS it no longer pauses. After `stopAutoRefresh()`, a return
  to the foreground no longer restarts it. Remove calls to `startAutoRefresh()` that only started
  auto refresh at launch. An app extension gets no lifecycle events, so auto refresh now runs there
  too. Set `autoRefresh: .disabled` in an extension that shares the session with its app.
- **`startAutoRefresh()` and `stopAutoRefresh()` take effect in order.** Each returns once its
  call took effect, so `await stopAutoRefresh()` followed by `await startAutoRefresh()` ends with
  auto refresh running. Under `.manual` and `.disabled`, `startAutoRefresh()` does nothing.
- **Opening a URL throws where the platform cannot.** On Linux, Android, and Windows,
  `linkIdentity(provider:scopes:redirectTo:queryParams:)` throws an `AuthError` of kind
  `.oauthFlowFailed`. v2 did nothing. Pass a `launchURL` closure instead.
- **A data request rejected for a stale token is retried once.** `SupabaseClient` sends a
  PostgREST, Storage, or Functions request again once when the server says it rejected the
  session's access token. PostgREST says so with a 401 whose `WWW-Authenticate` header carries
  `error="invalid_token"`. The Edge Functions gateway says so with a 401 whose `sb-error-code` is
  `UNAUTHORIZED_LEGACY_JWT` or `UNAUTHORIZED_ASYMMETRIC_JWT`. Storage says so with a 400 whose
  body has code `AccessDenied` and an expired-JWT message. Any other response reaches your code
  as before: a 401 that your function or your SQL returns, an RLS denial, and a Storage 400 with
  no body, such as the answer to a `HEAD`. When a newer token for the same user is already
  stored, the retry uses it. Otherwise the client refreshes the session first, except under
  `autoRefresh: .disabled`, where the rejection reaches your code. If another user signed in
  while the request ran, it is not retried. The rejection reaches your code when the refresh fails
  or the retry is rejected too. A request with a single-pass body, a request that sets its own
  `Authorization`, and a request sent without a session are not retried. An Edge Function with
  `verify_jwt` turned off that checks the token itself gets no retry. Storage `download(path:)`,
  `info(path:)`, and `exists(path:)` get no retry either: Storage answers an expired token there
  as an anonymous request, so a private bucket fails with code `NoSuchBucket` ("Bucket not
  found") and the response does not say that the token caused it. Remove your own
  refresh-and-retry code around these errors, but keep it around those three Storage calls if you
  need it.
- **Auth events are delivered asynchronously.** `onAuthStateChange` listeners and
  `authStateChanges` receive events in the order the session changed, but a listener can run after
  the call that caused the event returns. `didChangeAuthStateNotification` posts
  `.initialSession` once per client, not once per `onAuthStateChange` call.
- **No email or phone is `nil`.** `User.email` and `User.phone` are `nil`, not `""`, when the
  user has none. Search for `email == ""`, `phone == ""`, `email?.isEmpty`, and `phone?.isEmpty`.
- **No MFA factors is `[]`.** `User.factors` is `[]`, not `nil`, when the user has no factors.
  Search for `factors == nil` and `if let factors`.
- **An identity needs `identity_id`.** A `UserIdentity` without `identity_id` now fails to decode,
  and so does the `User` that holds it. v2 filled in the all-zero UUID, which
  `unlinkIdentity(_:)` then sent to the server. Search for `00000000-0000-0000-0000-000000000000`.
- **String `amr` entries are kept.** When a custom access token hook writes `amr` as strings,
  `authenticatorAssuranceLevel()` now returns them in `currentAuthenticationMethods`, with the
  token's `iat` as the `timestamp`. v2 dropped them.
- **MFA IDs print in uppercase.** Factor and challenge IDs are `UUID`. `"\(factor.id)"` is
  uppercase; compare `UUID` values, not strings.

## Renames and type changes

| v2 | v3 |
| --- | --- |
| `public actor AuthClient` | `public final class AuthClient: Sendable` |
| `GoTrueClient`, `GoTrueMFA`, `GoTrueLocalStorage`, `GoTrueMetaSecurity`, `GoTrueError` | `AuthClient`, `AuthMFA`, `AuthLocalStorage`, `AuthMetaSecurity`, `AuthError` |
| `JSONEncoder.goTrue`, `JSONDecoder.goTrue` | `AuthClient.Configuration.jsonEncoder`, `.jsonDecoder` |
| `MFAEnrollParams` | `MFATotpEnrollParams` or `MFAPhoneEnrollParams` |
| `AuthAdmin.deleteUser(id: String, shouldSoftDelete:)` | `AuthAdmin.deleteUser(id: UUID, shouldSoftDelete:)` |
| `AuthAdmin.getUserById(_:)` | `AuthAdmin.user(id:)` |
| `AuthAdminOAuth.getClient(clientId:)` | `AuthAdminOAuth.client(id:)` |
| `AuthAdminOAuth.updateClient(clientId:params:)` | `AuthAdminOAuth.updateClient(id:params:)` |
| `AuthAdminOAuth.deleteClient(clientId:)` | `AuthAdminOAuth.deleteClient(id:)` |
| `AuthAdminOAuth.regenerateClientSecret(clientId:)` | `AuthAdminOAuth.regenerateClientSecret(id:)` |
| `AuthOAuthServer.getAuthorizationDetails(authorizationId:)` | `AuthOAuthServer.authorizationDetails(id:)` |
| `AuthOAuthServer.approveAuthorization(authorizationId:)` | `AuthOAuthServer.approveAuthorization(id:)` |
| `AuthOAuthServer.denyAuthorization(authorizationId:)` | `AuthOAuthServer.denyAuthorization(id:)` |
| `AuthOAuthServer.revokeGrant(clientId:)` | `AuthOAuthServer.revokeGrant(id:)` |
| `AuthMFA.getAuthenticatorAssuranceLevel()` | `AuthMFA.authenticatorAssuranceLevel()` |
| `AuthClient.getOAuthSignInURL(...)` | `AuthClient.oauthSignInURL(...)` |
| `AuthClient.getLinkIdentityURL(...)` | `AuthClient.linkIdentityURL(...)` |
| `AuthClient.getClaims(jwt:options:)` | `AuthClient.claims(jwt:options:)` |
| `GetClaimsOptions.allowExpired` | `GetClaimsOptions.allowsExpired` |
| `AdminUserAttributes.emailConfirm`, `.phoneConfirm` | `AdminUserAttributes.confirmsEmail`, `.confirmsPhone` |
| `User.aud`, `ListUsersPaginatedResponse.aud`, `ListOAuthClientsPaginatedResponse.aud` | `.audience` |
| `AuthClient.Configuration.autoRefreshToken: Bool`, `.defaultAutoRefreshToken` | `.autoRefresh: AuthClient.AutoRefreshPolicy`; see below |
| `SupabaseClientOptions.AuthOptions.autoRefreshToken: Bool` | `.autoRefresh: AuthClient.AutoRefreshPolicy`; see below |
| `AuthClient(… fetch:)`, `AuthClient.Configuration(… fetch:)`, `AuthClient.FetchHandler` | `http:` (an `HTTPClientConfiguration`); see the overview |
| `Factor.id`, `AuthMFAEnrollResponse.id`, `AuthMFAUnenrollResponse.id`, every `factorId:` | `UUID` (was `String`) |
| `AuthMFAChallengeResponse.id`, `MFAVerifyParams.challengeId` | `UUID` (was `String`) |
| `OAuthClient.clientName`, `OAuthAuthorizationClient.name`, `OAuthAuthorizationUser.email`, `OAuthAuthorizationDetails.scope` | `String?` (was `String`) |
| `OAuthClient.redirectUris`, `.grantTypes`, `.responseTypes` | optional arrays |
| `enum` `AuthChangeEvent`, `FactorStatus`, `MessagingChannel`, `Provider`, `OpenIDConnectCredentials.Provider`, `MobileOTPType`, `EmailOTPType`, `ResendEmailType`, `ResendMobileType`, `SignOutScope` | `RawRepresentable` structs with the same member names |
| `AuthResponse`, `SSOResponse`, `OAuthClient`, `OAuthClientType`, `OAuthClientRegistrationType`, `OAuthAuthorization*`, `OAuthRedirect`, `OAuthGrant`, `JWK`, `JWKS`, `JWTHeader`, `JWTClaims`, `AudienceClaim`: `Codable` | `Decodable` |
| `OpenIDConnectCredentials`, `OpenIDConnectCredentials.Provider`, `AuthMetaSecurity`, `Web3Credentials`, `Web3Chain`, `UserAttributes`, `MessagingChannel`: `Codable` | `Encodable` |
| `OAuthResponse`, `Provider`: `Codable` | no `Codable` conformance |
| `UserCredentials` | internal |
| `UserAttributes.emailChangeToken` | removed |

For the structs that replace enums:

- An exhaustive `switch` needs a `default:` case.
- `if let x = Provider(rawValue: s)` does not compile; use `let x = Provider(rawValue: s)`.
- `Provider.allCases` and `EmailOTPType.allCases` are gone. Keep your own array.
- `Provider` is not `Identifiable`. Use `ForEach(providers, id: \.self)`.

For the MFA `UUID` changes, code that passes `factor.id` or `challenge.id` straight into another
MFA call still compiles. Use `.uuidString` and `UUID(uuidString:)` where you store strings.

## `AuthError` is a struct

`AuthError` is a struct with `kind`, `message`, `errorCode`, `weakPasswordReasons`,
`oauthError`, `response` and `underlyingError`. Match on `kind` and `errorCode` instead of enum
cases: `catch ErrorCode.invalidCredentials` and `catch AuthError.Kind.sessionMissing` compile.
`isRetryable` says whether to send the request again. `AuthError` is no longer `Equatable`.

| v2 | v3 |
| --- | --- |
| `catch AuthError.sessionMissing`, `AuthError.sessionNotFound` | `catch AuthError.Kind.sessionMissing` (nothing stored) or `catch AuthError.Kind.sessionInvalidated` (the server rejected the session) |
| `.api(message, errorCode, underlyingData, underlyingResponse)`, `AuthError.APIError` | `error.kind == .server`; `error.errorCode`, `error.response?.statusCode`, `error.response?.body`. The kind is `.sessionInvalidated` for the codes that end a session, and `.oauthFlowFailed` for `flow_state_not_found`, `flow_state_expired` and `bad_code_verifier` |
| `.weakPassword(message, reasons)` | `error.errorCode == .weakPassword`; `error.weakPasswordReasons` |
| `.pkceGrantCodeExchange(...)`, `.implicitGrantRedirect(message)`, `.pkce(_:)`, `.invalidImplicitGrantFlowURL`, `.invalidRedirectScheme` | `error.kind == .oauthFlowFailed` |
| `.jwtVerificationFailed(message)` | `error.kind == .jwtVerificationFailed` |
| `.refreshDiscarded` | `error.kind == .refreshDiscarded` |
| `.missingExpClaim`, `.malformedJWT`, `.missingURL` | removed |
| `error == .sessionMissing`, `AuthError.sessionMissing ~= error` | `AuthError.Kind.sessionMissing ~= error` |

```swift
// v2
do {
  try await supabase.auth.signIn(email: email, password: password)
} catch let AuthError.api(message, errorCode, _, response) {
  print(response.statusCode, errorCode, message)
} catch AuthError.sessionMissing {
  showLogin()
}
// v3
do {
  try await supabase.auth.signIn(email: email, password: password)
} catch let error as AuthError where error.kind == .server {
  print(error.response?.statusCode ?? 0, error.errorCode, error.message)
} catch AuthError.Kind.sessionMissing, AuthError.Kind.sessionInvalidated {
  showLogin()
}
```

`throw AuthError.sessionMissing` still compiles. `signInWithOAuth` now throws `.oauthFlowFailed`
when it has no redirect URL, where v2 trapped.

## `verifyOTP` returns `VerifyOTPResponse`

`verifyOTP` returns `VerifyOTPResponse` instead of `AuthResponse`. The first step of a secure email
change returns no session, so the result has a second case.

```swift
// v2
let response = try await supabase.auth.verifyOTP(tokenHash: hash, type: .emailChange)
let email = response.user.email
// v3
let response = try await supabase.auth.verifyOTP(tokenHash: hash, type: .emailChange)
switch response {
case .session(let session):
  let email = session.user.email
case .emailChangeConfirmationPending(let confirmation):
  print(confirmation.message, confirmation.code)
}
```

## `emitLocalSessionAsInitialSession` is removed

Remove the parameter from `AuthClient.init`, `AuthClient.Configuration.init` and
`SupabaseClientOptions.AuthOptions.init`. The v2 `true` behavior is now the only behavior. See
"Initial session can be expired" above.

```swift
// v2
for await (event, session) in supabase.auth.authStateChanges {
  if event == .initialSession, let session { signIn(user: session.user) }
}
// v3
for await (event, session) in supabase.auth.authStateChanges {
  if event == .initialSession, let session, !session.isExpired { signIn(user: session.user) }
}
```

## Custom `encoder` and `decoder` are removed

`AuthClient` and `AuthClient.Configuration` no longer take `encoder:` or `decoder:`, and
`SupabaseClientOptions.AuthOptions` no longer has them. Auth always uses its own JSON coders.

```swift
// v2
let auth = AuthClient(url: url, localStorage: storage, encoder: myEncoder, decoder: myDecoder)
// v3
let auth = AuthClient(url: url, localStorage: storage)
```

## `autoRefreshToken` is `autoRefresh`

`autoRefreshToken: true` is `autoRefresh: .automatic`, the default. `autoRefreshToken: false` is
`autoRefresh: .manual`: `session` still refreshes an expired session, and nothing refreshes it
ahead of time. The new `.disabled` never refreshes on its own, and `session` throws an
`AuthError` of kind `.refreshDisabled` when the session is expired. Use it in an app extension
that shares the session with its app. `observesAppLifecycle: false` stops the client
from following the app lifecycle, so you can drive it from a SwiftUI `scenePhase` change. Call
`refreshSessionIfNeeded()` from a `BGAppRefreshTask` to renew the session in the background.

```swift
// v2
let supabase = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(auth: .init(autoRefreshToken: false))
)
// v3
let supabase = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(auth: .init(autoRefresh: .manual))
)
```

## `AuthClient` is not an actor

Remove `isolated AuthClient` parameters and `assumeIsolated` calls.

```swift
// v2
func inspect(_ auth: isolated AuthClient) { print(auth.currentUser?.email ?? "") }
// v3
func inspect(_ auth: AuthClient) { print(auth.currentUser?.email ?? "") }
```

## `WinCredLocalStorage` is removed

`WinCredLocalStorage` and `WinCredLocalStorageError` are removed. On Windows, as on Linux and
Android, `AuthClient.Configuration.defaultLocalStorage` keeps the session in memory, so the user
must sign in again after the app exits. The v2 type could not read back what it wrote, so no stored
session is lost. To persist the session, pass your own `AuthLocalStorage`.

```swift
// v2 (Windows)
let supabase = SupabaseClient(supabaseURL: url, supabaseKey: key)
// v3 (Windows)
struct MyLocalStorage: AuthLocalStorage {
  func store(key: String, value: Data) throws { /* ... */ }
  func retrieve(key: String) throws -> Data? { /* return nil when missing */ }
  func remove(key: String) throws { /* ... */ }
}
let supabase = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(auth: .init(storage: MyLocalStorage()))
)
```

On macOS, `KeychainLocalStorage(useDataProtectionKeychain: true)` is a new opt-in that removes the
Keychain consent prompt. It needs a provisioning profile with Keychain entitlements.

## Experimental APIs

Passkeys and WebAuthn MFA are `@_spi(Experimental)`. Import them with
`@_spi(Experimental) import Supabase` (or `import Auth`). They may change in any release. In v3,
`getPasskeyRegistrationOptions()` and `getPasskeyAuthenticationOptions()` drop the `get` prefix,
`AuthAdmin.listPasskeys(userId:)` is `listPasskeys(forUser:)`, and
`AuthAdmin.deletePasskey(userId:passkeyId:)` is `deletePasskey(id:forUser:)`.
