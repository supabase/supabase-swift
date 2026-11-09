# Auth v3 migration

This file covers the changes to `AuthClient`, sessions, MFA, OAuth, `AuthError` and local storage
from v2 to v3. See [the v3 migration overview](../../../V3_MIGRATION.md) for steps that apply to
every module.

## Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **`Session`, `User`, `UserIdentity` and `Factor` encode with snake_case keys.** They declare
  their own keys now, so any coder writes `access_token`, not `accessToken`. If your app stores
  these values with its own `JSONEncoder` (a `UserDefaults` or keychain cache), it writes
  `access_token` from now on, and a blob that it wrote earlier with `accessToken` no longer
  decodes. Clear such a cache or decode the old blob with your own keys. The SDK's own session
  storage reads every earlier format.
- **Free-form keys are no longer rewritten.** The v2 Auth coders converted every key between
  `camelCase` and `snake_case`, including the keys of your own JSON, such as `userMetadata` and
  `data`. v3 maps only the declared model keys, so the keys that you send and read stay as you
  wrote them. If your app or a database trigger relied on the conversion, for example by sending
  `firstName` and reading `first_name`, send and read the key you mean.
- **Initial session can be expired.** With `autoRefresh: .automatic`, the client tries one
  refresh of an expired stored session before it delivers `.initialSession`. It waits at most
  `AuthClient.Configuration.initialRefreshTimeout`, 5 seconds by default. A value of zero or less
  turns the refresh off. On a launch into the background it runs too, as it does not wait for the
  app to come to the foreground.
  - The refresh succeeds: `.initialSession` carries the new session.
  - The server rejects the refresh token: `.initialSession` carries
    `.signedOut(.sessionExpired)` or `.signedOut(.sessionRevoked)`.
  - The refresh fails for another reason, such as no network, or does not finish in time:
    `.initialSession` carries the expired session. A refresh that is still running then commits
    as `.tokenRefreshed`, or, when the server rejects the refresh token, ends the session with
    `.signedOut`.

  With `.manual` or `.disabled`, `.initialSession` fires at once with the stored session. Check
  `session.isExpired()` in handlers that switch on `.initialSession`.
- **The stored session loads asynchronously.** `AuthStorage` is `async`, so a new client has
  `status == .loading` and `currentSession == nil` until it has read storage. v2 read storage
  before `init` returned. Call `await auth.initialization()`, or wait for the first
  `.initialSession` event from `events()`, before you read `currentSession`.
- **`KeychainStorage` returns `nil` for a missing key.** `load(key:)` does not throw when no item
  exists, and `remove(key:)` on a missing key does nothing. Remove `catch` blocks that treated an
  error as "no session". A custom `AuthStorage` must follow the same contract.
- **The stored session stays on this device.** The default storage writes Keychain items with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; v2 used
  `kSecAttrAccessibleAfterFirstUnlock`. The first save after the upgrade, such as a token refresh,
  moves a v2 item to the new class in place, so the user stays signed in. A backup restored to
  another device no longer carries the session, and the user signs in again there. macOS keeps the
  file-based Keychain, which has no accessibility class. To keep the v2 behavior, pass
  `storage: KeychainStorage(accessibility: .afterFirstUnlock, useDataProtectionKeychain: false)`.
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
- **Auth logs and descriptions hide secrets.** The Auth logger removes access, refresh, provider
  and ID tokens, PKCE verifiers, authorization codes, OTP codes and passwords from every line, and
  cuts the query and fragment off logged URLs. `"\(session)"` prints
  `Session(user_id: …, expires_at: …)` and `"\(change)"` on an `AuthChange` prints its masked
  session. Read `session.accessToken` or `session.refreshToken` when you need a token. `dump(_:)` and
  `customDump(_:)` still print every field. Search for
  code that parses a printed `Session` or `AuthChange`, or that reads a token or URL query from
  an Auth log line.
- **A rejected session has its own kind.** When the server rejects the session or its refresh
  token (`refresh_token_not_found`, `refresh_token_already_used`, `session_expired`,
  `session_not_found`, `user_banned`), the error kind is `.sessionInvalidated`, not
  `.sessionMissing`. `code` and `message` keep the server's values. `.sessionMissing` now
  means only that no session is stored. Search for `.sessionMissing`. To send the user back to
  sign-in, react to the `.signedOut` event (see the next entry on refresh failures).
- **The stored session has a new format.** The first read after the upgrade rewrites the stored
  session in a versioned format with snake_case keys and ISO 8601 dates, and moves a session
  stored under the old `supabase.session` key to the configured key. v2 cannot read the new
  format, so going back to v2 signs users out. Code that reads the session JSON from your
  `AuthStorage` directly must read the new format.
- **Storage errors surface.** When `storage` throws while the client saves or removes the
  session, the call that changed the session (a sign-in, `refreshSession`, `signOut`) throws that
  error and the session stays as it was. v2 logged the error and went on. When the read at launch
  throws, `currentSession` is `nil` and `session()` throws the storage error, not `.sessionMissing`;
  v2 read a failed read as signed out.
- **A locked Keychain is not signed out.** `KeychainStorage` throws an `AuthError` of kind
  `.storageUnavailable` while the device is locked (`errSecInteractionNotAllowed`), and of kind
  `.storageMisconfigured` when the app lacks the Keychain entitlement (`errSecMissingEntitlement`).
  v2 threw an internal Keychain error, and a launch into the background before the first unlock
  emitted `.initialSession` with no session. Now `.initialSession` waits until storage is read.
  Until then, each call that needs the session reads storage again: `session()`,
  `refreshSessionIfNeeded`, a request that sends the session's access token (such as `user()` or a
  `SupabaseClient` data request), each new `events()` stream, and `initialization()`. `session()` throws `.storageUnavailable` while the device is locked. On iOS, iPadOS,
  tvOS, visionOS, and Mac Catalyst the client also reads storage when protected data becomes
  available. watchOS and macOS post no such notification, so there only those calls read storage
  again. A sign-in that throws `.storageUnavailable` did not sign in, so retry it after the device
  unlocks. The client also reports the first `.storageMisconfigured` error from its storage as a
  runtime issue, whether a read at launch or a later write, such as the save of a sign-in, throws
  it. On macOS with `useDataProtectionKeychain: true` and no entitlement, a read finds no item, so
  the report comes from the first sign-in.
- **Unit tests with the default storage report an issue.** A test bundle with no host app on an
  iOS, tvOS, visionOS, or watchOS simulator has no Keychain entitlement. A test there that creates
  a client with the default `KeychainStorage` now records a runtime issue when it creates the
  client, and Swift Testing and XCTest fail the test. Pass storage that keeps values in memory in
  tests:

  ```swift
  let client = try SupabaseClient(
    supabaseURL: url,
    supabaseKey: key,
    configuration: .init(auth: .init(storage: InMemoryAuthStorage()))
  )
  ```
- **The stored session is read once.** The client reads `storage` once, right after it is created, and
  keeps the session in memory. `currentSession` no longer reads storage, so a session that other
  code (an app extension, another process) writes to the same storage is not seen until the next
  client is created.
- **Each client keeps its own session in memory.** Because the session is read once, two
  clients with the same storage and storage key do not see each other's changes. When one
  refreshes, the other still holds the old refresh token, and its next refresh fails with
  `refresh_token_already_used`. On the first such refresh after its session expires, it reads
  storage again: when storage holds the newer session, it takes that session and emits
  `tokenRefreshed` (`signedIn` for another user); otherwise it signs out. Create one client per
  project, or give each client its own `storageKey`.
- **Refreshes are deduplicated and throttled.** A client runs one refresh of a refresh token at a
  time. A cancelled caller of `session()` or `refreshSession()` throws `CancellationError` at once,
  and the shared refresh still finishes. When a refresh fails, a new refresh with that same token
  in the next 60 seconds throws the same error without a request. After five refreshes in 30
  seconds, the next one throws an `AuthError` with kind `.excessiveRefresh`. `signOut` cancels a
  running refresh. Its callers get `CancellationError`, whatever error the request then ends
  with, or `.refreshDiscarded` when a successful response arrived first. Search for retry loops
  around `refreshSession`.
- **`signOut()` signs out only this device.** The default scope is `.local`, not `.global`, so
  the user's sessions on other devices stay. Pass `scope: .global` to keep the v2 behavior. The
  scopes also handle failures differently:
  - `.local` removes the session, clears pending PKCE flows, and emits `.signedOut` before the
    request, so the device is signed out whatever the server answers.
  - `.global` removes the session only after the server ended every session. When the request
    fails, the session stays, and `signOut` throws, so you can retry or fall back to `.local`. v2
    removed it first.
  - `.others` never changes the local session, and throws `.sessionMissing` when no session is
    stored. v2 returned without an error.

  v2 ignored a 401, 403, or 404 from the server. v3 ignores only `403 user_not_found`, and
  `403 session_not_found` for `.local`; every other failure throws. With no stored session,
  `.local` and `.global` still emit `.signedOut`. Search for `signOut(`.
- **`claims()` throws the refresh error.** When `claims()` reads the session and its refresh
  fails, it throws that error. v2 threw `.sessionMissing` for every failure.
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
  `importSession(accessToken:refreshToken:)` or `user(jwt:)` with another token or while signed out, never
  signs out and fires no event.
- **Expiry follows the local clock, and auto refresh runs on a deadline.** The client judges
  expiry from the local time it received the session plus `expiresIn`, not from `expiresAt`
  against the device clock. On a device whose clock is wrong, `session()` no longer refreshes on
  every call, and `Session.isExpired(at:leeway:)` agrees with it. `startAutoRefresh()` no longer checks the session every
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
- **Pending v2 OAuth flows cannot finish.** v3 keeps PKCE flows in its own store and does not
  read the v2 code verifier. A user who started a sign-in, a password reset, or an identity link
  with v2 and returns after the upgrade gets an `AuthError` of kind `.oauthFlowFailed`. Ask the user
  to start again.
- **`handleRedirect(_:)` ignores URLs that are not auth redirects.** v2's `session(from:)` threw
  for them. v3 returns `nil`. Search for `catch` blocks that showed an "invalid URL" message.
- **A redirect with tokens signs in without a pending flow.** `handleRedirect(_:)` accepts a URL
  with implicit tokens (`#access_token=…`), as email links without PKCE and `generateLink` send.
  It signs in the account that the tokens belong to, whoever made the URL. Pass only URLs that
  reach your own callback, so another app or a web page cannot sign the user in to its account.
- **The same redirect URL is handled once.** A second delivery of a URL (a scene delegate and
  `onOpenURL` both fire) returns the first result and sends no request. v2 sent the code again and
  failed.
- **`exchangeCodeForSession` needs a pending flow.** With no stored flow for the code, it throws
  `.oauthFlowFailed` without a request. v2 sent the code with no verifier.
- **Several PKCE flows can be pending.** v2 kept one code verifier, so a new sign-in replaced the
  old one. In v3 each flow has its own verifier. Pass the `id` of the `OAuthFlow` from
  `oauthSignInURL`, `linkIdentityURL`, or `ssoSignInURL` to `exchangeCodeForSession` to pick
  one. Without it, as for the code in an email link, the client tries the pending flows newest
  first.
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
- **Auth events are delivered asynchronously.** `events()` delivers changes in the order the
  session changed, but your loop can run after the call that caused the change returns. Read
  `auth.status` or `auth.currentSession` for the state right after a call.
- **OTP and recovery events follow the flow.** `verifyOTP` with type `.recovery` emits
  `.passwordRecovery`. With `.emailChange` or `.phoneChange` it emits `.userUpdated` when the
  same user is signed in, and `.signedIn` otherwise. v2 emitted `.signedIn` for all of them. `session(from:)` for a recovery link emits only
  `.passwordRecovery`; v2 emitted `.signedIn` first. With the PKCE flow, the code exchange after
  `resetPassword(email:)` also emits `.passwordRecovery`, not `.signedIn`. The exchange after an
  email change (`updateUser(_:redirectTo:)` with an email, or `resend(type: .emailChange)`) follows the
  `verifyOTP` rule above. Search for `.signedIn`
  handlers that expect these flows.
- **`unlinkIdentity` updates the user.** It removes the identity from `currentUser`, and its
  provider from `appMetadata["providers"]` when no other identity uses it. Then it emits
  `.userUpdated`. v2 emitted nothing and kept the identity in `currentUser`.
- **No email or phone is `nil`.** `User.email` and `User.phone` are `nil`, not `""`, when the
  user has none. Search for `email == ""`, `phone == ""`, `email?.isEmpty`, and `phone?.isEmpty`.
- **No MFA factors is `[]`.** `User.factors` is `[]`, not `nil`, when the user has no factors.
  The type is still `[Factor]?`, so `user.factors ?? []` is the way to read it. Search for
  `factors == nil` and `if let factors`.
- **An identity needs `identity_id`.** A `UserIdentity` without `identity_id` now fails to decode,
  and so does the `User` that holds it. v2 filled in the all-zero UUID, which
  `unlinkIdentity(_:)` then sent to the server. Search for `00000000-0000-0000-0000-000000000000`.
- **`UserIdentity.id` is the identity UUID.** `"\(identity.id)"` now prints the identity UUID,
  not the provider's user ID, and `ForEach(identities)` keys on the identity UUID. Search for
  `identity.id` and `\.id` on identities. See "`UserIdentity.id` is the identity UUID" below.
- **String `amr` entries are kept.** When a custom access token hook writes `amr` as strings,
  `assuranceLevel()` now returns them in `currentAuthenticationMethods`, with the token's `iat` as
  the `timestamp`. v2 dropped them.
- **MFA string values are structs.** `FactorType`, `AuthenticatorAssuranceLevel` (also
  `VerifiedClaims.assuranceLevel`, the `aal` claim), and `AuthenticationMethod` (`AMREntry.method`)
  were `String`. `==` and string literals still work, but `"\(factor.factorType)"` prints
  `FactorType(rawValue: "totp")`. Search for interpolations of `factorType`, `currentLevel`,
  `nextLevel`, `aal`, `assuranceLevel`, and `method`, and use `.rawValue`.
- **MFA IDs print in uppercase.** Factor and challenge IDs are `UUID`. `"\(factor.id)"` is
  uppercase; compare `UUID` values, not strings.
- **`claims()` throws the refresh error.** When the stored session is expired and its refresh
  fails, `claims()` throws the error that `session` throws, such as `.sessionInvalidated` with
  `code` `refresh_token_not_found`. v2 threw `.sessionMissing` for every failure to get a
  session. `.sessionMissing` now means only that no user is signed in.
- **A token without `exp` or `sub` fails verification.** `claims(jwt:)` throws
  `.jwtVerificationFailed` for a token without an `exp` claim or a `sub` claim, before it sends
  any request. The anon key and the service role key have no `sub`, so `claims(jwt:)` rejects
  them. An expired token also fails before any request, unless you pass
  `ClaimsOptions(allowsExpired: true)`. v2 accepted a token without `exp`.
- **Each client caches its own key set.** `claims()` caches the JWKS per client for 10 minutes.
  v2 shared one cache between clients with the same storage key, so each new client now fetches
  the key set once. A token whose key is not in the cached set triggers a new fetch, so rotated
  keys resolve without waiting for the cache to expire.
- **Admin calls have no default redirect.** `AuthAdminClient` does not read
  `AuthClient.Configuration.redirectTo`. `inviteUser` and `generateLink` send `redirect_to`
  only when you pass `redirectTo:`; without it, the server uses its site URL.

## Renames and type changes

| v2 | v3 |
| --- | --- |
| `public actor AuthClient` | `public final class AuthClient: Sendable` |
| `GoTrueClient`, `GoTrueMFA`, `GoTrueError` | `AuthClient`, `AuthMFA`, `AuthError` |
| `GoTrueLocalStorage`, `AuthLocalStorage` (`store`, `retrieve`, `remove`) | `AuthStorage` (`async`: `save(_:key:)`, `load(key:)`, `remove(key:)`); see below |
| `KeychainLocalStorage`, `WinCredLocalStorage` | `KeychainStorage`, `InMemoryAuthStorage`; see below |
| `AuthClient.Configuration.localStorage:`, `AuthOptions.storage: any AuthLocalStorage` | `storage: any AuthStorage`; `nil` or omitted uses the platform default |
| `AuthClient.Configuration.defaultLocalStorage` | removed; leave `storage` out |
| `AuthClient.Configuration.url: URL?` (default `http://localhost:9999`) | `url: URL`, required |
| `AuthClient.Configuration.storageKey: String?` (default `supabase.auth.token`) | `storageKey: String`, required; `SupabaseClient` derives `sb-<project-ref>-auth-token` |
| `AuthClient.Configuration.headers: [String: String]` | `HTTPFields` |
| `AuthClient.Configuration.redirectToURL` | `redirectTo` |
| `SupabaseClientOptions.AuthOptions.redirectToURL`, `AuthOptions(redirectToURL:)` | `SupabaseClient.Configuration.Auth.redirectTo`, `Auth(redirectTo:)`; `SupabaseClient` passes it to `AuthClient.Configuration.redirectTo` |
| `AuthClient.Configuration` `let` properties | `var` properties |
| `AuthClient.Configuration.defaultHeaders` | removed |
| `AuthMetaSecurity`, `GoTrueMetaSecurity` | internal; pass `captchaToken:` |
| `signInWithIdToken(credentials:)`, `signInWithWeb3(credentials:)` | `signInWithIDToken(_:)`, `signInWithWeb3(_:)` |
| `linkIdentityWithIdToken(credentials:)` | `linkIdentity(idToken:)` |
| `user(jwt: String? = nil)` | `user()` for the signed-in user, `user(jwt:)` with a token; `jwt` is a `String`, not a `String?` |
| `update(user:redirectTo:)` | `updateUser(_:redirectTo:)` |
| `userIdentities()` | `identities()` |
| `OpenIDConnectCredentials(provider:idToken:accessToken:nonce:gotrueMetaSecurity:)` | `IDTokenCredentials(provider:idToken:nonce:accessToken:captchaToken:)` |
| `OpenIDConnectCredentials.Provider` | `Provider` |
| `Web3Credentials.gotrueMetaSecurity` | `Web3Credentials.captchaToken` |
| `signInAnonymously(data:)`, `signInWithOTP(…data:…)`, `UserAttributes.data`, `UserAttributes(…data:)` | `userMetadata:` (a `JSONObject`; empty sends nothing) |
| `JSONEncoder.goTrue`, `JSONDecoder.goTrue`, `AuthClient.Configuration.jsonEncoder`, `.jsonDecoder` | removed; Auth always uses its own JSON coders |
| `AuthMFA.enroll(params:)`, `MFAEnrollParams`, `MFAEnrollParamsType`, `MFATotpEnrollParams`, `MFAPhoneEnrollParams` | `AuthMFA.enrollTOTP(issuer:friendlyName:)`, `AuthMFA.enrollPhone(_:friendlyName:)`; see below |
| `AuthMFA.challenge(params:)`, `MFAChallengeParams` | `AuthMFA.challenge(factorID:channel:)` |
| `AuthMFA.verify(params:)`, `MFAVerifyParams` | `AuthMFA.verify(factorID:challengeID:code:)` |
| `AuthMFA.challengeAndVerify(params:)`, `MFAChallengeAndVerifyParams` | `AuthMFA.challengeAndVerify(factorID:code:)` |
| `AuthMFA.unenroll(params:)`, `MFAUnenrollParams` | `AuthMFA.unenroll(factorID:)`, which still returns `AuthMFAUnenrollResponse` |
| `AuthMFA.listFactors()`, `AuthMFAListFactorsResponse` | `AuthMFA.factors()`, `MFAFactors`; see below |
| `AuthMFAEnrollResponse` | `TOTPEnrollment` (`totp.qrCode` is `qrCode`), `PhoneEnrollment` |
| `AuthMFAChallengeResponse`, `.type`, `.expiresAt: TimeInterval` | `MFAChallenge`, `.factorType`, `.expiresAt: Date` |
| `AuthMFAVerifyResponse` | `Session` |
| `typealias FactorType = String`, `AuthenticatorAssuranceLevels`, `AMREntry.Method` | `RawRepresentable` structs `FactorType`, `AuthenticatorAssuranceLevel`, `AuthenticationMethod` |
| `AMREntry.timestamp: TimeInterval` | `Date` |
| `Session.expiresAt: TimeInterval`, `Session.expiresIn: TimeInterval` | `expiresAt: Date`, `expiresIn: Duration`; see below |
| `Session.isExpired: Bool` | `Session.isExpired(at:leeway:)`; see below |
| `PasskeyRegistrationOptions.expiresAt: TimeInterval`, `PasskeyAuthenticationOptions.expiresAt: TimeInterval` | `Date` |
| `AuthClient.admin`, `AuthAdmin` | `AuthAdminClient(configuration: .init(url:secretKey:))`; see below |
| `AuthAdmin.deleteUser(id: String, shouldSoftDelete:)` | `AuthAdminClient.deleteUser(id: UUID, softDelete:)` |
| `AuthAdmin.getUserById(_:)` | `AuthAdminClient.user(id:)` |
| `AuthAdmin.updateUserById(_:attributes:)` | `AuthAdminClient.updateUser(id:attributes:)` |
| `AuthAdmin.createUser(attributes:)` | `AuthAdminClient.createUser(_:)` |
| `AuthAdmin.inviteUserByEmail(_:data:redirectTo:)` | `AuthAdminClient.inviteUser(email:userMetadata:redirectTo:)`; `userMetadata` is a `JSONObject` |
| `AuthAdmin.listUsers(params: PageParams(page:perPage:))` | `AuthAdminClient.listUsers(page:pageSize:)`; `users(pageSize:)` returns a `PageSequence` over every page |
| `ListUsersPaginatedResponse` | `UserPage`, with only `let` properties |
| `AuthAdmin.generateLink(params:)` | `AuthAdminClient.generateLink(_:)` |
| `GenerateLinkProperties.redirectTo: URL` | `URL?` |
| `AdminUserAttributes.id: String?` | `UUID?` |
| `AdminUserAttributes.banDuration: String?` (`"24h"`, `"none"`) | `Duration?` (`.seconds(86_400)`, `.zero` to lift the ban) |
| `AuthAdminOAuth.getClient(clientId:)` | `AuthAdminOAuth.client(id:)` |
| `AuthAdminOAuth.updateClient(clientId:params:)` | `AuthAdminOAuth.updateClient(id:params:)` |
| `AuthAdminOAuth.deleteClient(clientId:)` | `AuthAdminOAuth.deleteClient(id:)` |
| `AuthAdminOAuth.regenerateClientSecret(clientId:)` | `AuthAdminOAuth.regenerateClientSecret(id:)` |
| `AuthOAuthServer.getAuthorizationDetails(authorizationId:)` | `AuthOAuthServer.authorizationDetails(id:)` |
| `AuthOAuthServer.approveAuthorization(authorizationId:)` | `AuthOAuthServer.approveAuthorization(id:)` |
| `AuthOAuthServer.denyAuthorization(authorizationId:)` | `AuthOAuthServer.denyAuthorization(id:)` |
| `AuthOAuthServer.revokeGrant(clientId:)` | `AuthOAuthServer.revokeGrant(id:)` |
| `AuthMFA.getAuthenticatorAssuranceLevel()`, `AuthMFAGetAuthenticatorAssuranceLevelResponse` | `AuthMFA.assuranceLevel()`, `AssuranceLevelInfo`; see below |
| `AuthClient.getOAuthSignInURL(...)` | `AuthClient.oauthSignInURL(...)` |
| `AuthClient.getLinkIdentityURL(...)` | `AuthClient.linkIdentityURL(...)` |
| `getOAuthSignInURL(...)` returns `URL` | `oauthSignInURL(_:options:)` returns `OAuthFlow` (`id`, `url`) |
| `getLinkIdentityURL(...)` returns `OAuthResponse` (`provider`, `url`) | `linkIdentityURL(_:options:)` returns `OAuthFlow` (`id`, `url`) |
| `exchangeCodeForSession(authCode:)` | `exchangeCodeForSession(_:flowID:)`, `flowID` is an optional `UUID` |
| `AuthClient.handle(_:)`, `SupabaseClient.handle(_:)` | `handleRedirect(_:)` (`async throws`); see below |
| `AuthClient.session(from:)` | `handleRedirect(_:)`; see below |
| `AuthClient.Configuration.flowType`, `AuthOptions.flowType`, `AuthFlowType`, `defaultFlowType` | removed; see below |
| `AuthClient(url:headers:localStorage:…)` | `AuthClient(configuration:)`; see below |
| `AuthClient.getClaims(options:)` (no `jwt`) | `AuthClient.claims(options:)` |
| `AuthClient.getClaims(jwt:options:)` with a token | `AuthClient.claims(jwt:options:)`; `jwt` is a `String`, not a `String?` |
| `GetClaimsOptions`, `GetClaimsOptions(allowExpired:jwks:)` | `ClaimsOptions`, `ClaimsOptions(allowsExpired:jwks:)` |
| `try await auth.session` | `try await auth.session()` |
| `AuthClient.setSession(accessToken:refreshToken:)` | `AuthClient.importSession(accessToken:refreshToken:)`; it emits only `.signedIn`, not `.tokenRefreshed` then `.signedIn` |
| `AuthClient.refreshSession(refreshToken:)` | `AuthClient.refreshSession()`; see below |
| `AdminUserAttributes.emailConfirm`, `.phoneConfirm` | `AdminUserAttributes.confirmsEmail`, `.confirmsPhone` |
| `User.aud`, `ListUsersPaginatedResponse.aud`, `ListOAuthClientsPaginatedResponse.aud` | `.audience` (`UserPage.audience` for users) |
| `AuthClient.Configuration.autoRefreshToken: Bool`, `.defaultAutoRefreshToken` | `.autoRefresh: AuthClient.AutoRefreshPolicy`; see below |
| `SupabaseClientOptions.AuthOptions.autoRefreshToken: Bool` | `SupabaseClient.Configuration.Auth.autoRefresh: AuthClient.AutoRefreshPolicy`; see below |
| `AuthClient(… fetch:)`, `AuthClient.Configuration(… fetch:)`, `AuthClient.FetchHandler` | `http:` (an `HTTPClientConfiguration`); see the overview |
| `AuthClient.Configuration(url:storageKey:headers:storage:redirectTo:logger:http:autoRefresh:...)` | `AuthClient.Configuration(url:storageKey:headers:storage:redirectTo:autoRefresh:observesAppLifecycle:initialRefreshTimeout:http:logger:clock:now:)`; `AuthClient.configuration` is public |
| `Factor.id`, `AuthMFAEnrollResponse.id`, `AuthMFAUnenrollResponse.id`, every `factorId:` | `UUID` (was `String`); the labels are `factorID:` |
| `AuthMFAChallengeResponse.id`, `MFAVerifyParams.challengeId` | `MFAChallenge.id`, `challengeID:`: `UUID` (was `String`) |
| `OAuthClient.clientName`, `OAuthAuthorizationClient.name`, `OAuthAuthorizationUser.email`, `OAuthAuthorizationDetails.scope` | `String?` (was `String`) |
| `OAuthClient.redirectUris`, `.grantTypes`, `.responseTypes` | optional arrays |
| `enum MobileOTPType`, `enum ResendMobileType` | `struct PhoneOTPType`, `struct ResendPhoneType`, `RawRepresentable` with the same member names |
| `resetPasswordForEmail(_:redirectTo:captchaToken:)` | `resetPassword(email:options:)` with `ResetPasswordOptions(redirectTo:captchaToken:)` |
| `resend(email:type:emailRedirectTo:captchaToken:)` | `resend(email:type:options:)` with `ResendEmailOptions(redirectTo:captchaToken:)` |
| `resend(phone:type:captchaToken:)` returns `ResendMobileResponse` | `resend(phone:type:options:)` with `ResendPhoneOptions(captchaToken:)`; returns `MessageID?`, read `.rawValue` for the string |
| `verifyOTP(email:token:type:redirectTo:captchaToken:)`, `verifyOTP(phone:token:type:captchaToken:)` | `verifyOTP(email:token:type:)`, `verifyOTP(phone:token:type:)`; the server checks no `redirect_to` and no captcha token on this call |
| `enum AuthChangeEvent` | `struct AuthEvent` with the same member names; `.userDeleted` is removed, because the client never emitted it |
| `enum` `FactorStatus`, `MessagingChannel`, `Provider`, `EmailOTPType`, `ResendEmailType` | `RawRepresentable` structs with the same member names |
| `OAuthClient`, `OAuthClientType`, `OAuthClientRegistrationType`, `OAuthAuthorization*`, `OAuthRedirect`, `OAuthGrant`, `JWK`, `JWKS`, `JWTHeader`: `Codable` | `Decodable` |
| `Web3Chain`, `UserAttributes`, `MessagingChannel`: `Codable` | `Encodable` |
| `OpenIDConnectCredentials`, `Web3Credentials`: `Codable` | `IDTokenCredentials`, `Web3Credentials`: no `Codable` conformance |
| `AMREntry`: `Decodable` | no `Codable` conformance |
| `UserCredentials` | internal |
| `UserIdentity.id` (the provider's user ID, a `String`) | `UserIdentity.providerUserID`; `id` is now the identity UUID; see below |
| `UserIdentity.identityId` | `UserIdentity.id` |
| `UserIdentity.userId` | `UserIdentity.userID` |
| `UserIdentity.provider: String` | `UserIdentity.provider: Provider` |
| `UserIdentity.identityData: [String: JSONValue]?` | `UserIdentity.identityData: JSONObject`; `[:]` when the server sends none |
| `UserIdentity(id:identityId:userId:identityData:provider:createdAt:lastSignInAt:updatedAt:)` | `UserIdentity(id:providerUserID:userID:provider:identityData:email:createdAt:lastSignInAt:updatedAt:)` |
| `UserAttributes.emailChangeToken` | removed |

For the structs that replace enums:

- An exhaustive `switch` needs a `default:` case.
- `if let x = Provider(rawValue: s)` does not compile; use `let x = Provider(rawValue: s)`.
- `Provider.allCases` and `EmailOTPType.allCases` are gone. Keep your own array.
- `Provider` is not `Identifiable`. Use `ForEach(providers, id: \.self)`.

For the MFA `UUID` changes, code that passes `factor.id` or `challenge.id` straight into another
MFA call still compiles. Use `.uuidString` and `UUID(uuidString:)` where you store strings.

## Acronyms use uniform case

Every public Auth name spells `ID`, `URL` and `URI` in capitals, like `factorID` and `jwksURI`. The
wire keys do not change.

| v3 pre-release | v3 |
| --- | --- |
| `OAuthClient.clientId`, `.clientUri`, `.logoUri`, `.redirectUris` | `clientID`, `clientURI`, `logoURI`, `redirectURIs` |
| `CreateOAuthClientParams` and `UpdateOAuthClientParams`: `clientUri`, `logoUri`, `redirectUris` | `clientURI`, `logoURI`, `redirectURIs` |
| `OAuthAuthorizationClient.logoUri` | `logoURI` |
| `OAuthAuthorizationDetails.authorizationId`, `.redirectUri` | `authorizationID`, `redirectURI` |
| `WebAuthnChallengeOptions.rpId` | `rpID` |
| The `userId:` parameter of the admin MFA and passkey methods | `userID:` |
| `CustomProvider` URL and ID fields (`clientId`, `discoveryUrl`, `authorizationUrl`, `tokenUrl`, `userinfoUrl`, `jwksUri`, `acceptableClientIds`) | `clientID`, `discoveryURL`, `authorizationURL`, `tokenURL`, `userinfoURL`, `jwksURI`, `acceptableClientIDs` |
| `OAuthRedirect.redirectURL` and `OAuthAuthorizationDetails.redirectUri` | `redirectURL` and `redirectURI` stay two names: the first is a full URL the app opens, the second is the client's registered URI |

## `admin` is a separate `AuthAdminClient`

`AuthClient.admin` is removed. Create an `AuthAdminClient` with the secret key on your server. It
sets the `apikey` and `Authorization` headers itself and never touches a user session. Do not ship
the secret key in an app.

```swift
// v2
let supabase = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: secretKey)
try await supabase.auth.admin.deleteUser(id: userID)
// v3
let admin = AuthAdminClient(
  configuration: .init(
    url: supabaseURL.appendingPathComponent("auth/v1"),
    secretKey: secretKey
  )
)
try await admin.deleteUser(id: userID)
```

## `refreshSession(refreshToken:)` is gone

`refreshSession()` refreshes only the stored session. To sign in with a refresh token from
elsewhere, pass both tokens to `importSession`. It redeems the refresh token when the access token
has expired.

```swift
// v2
let session = try await auth.refreshSession(refreshToken: refreshToken)
// v3
let session = try await auth.importSession(accessToken: accessToken, refreshToken: refreshToken)
```

## OAuth has one entry point

v2 had `signInWithOAuth` with a `launchFlow:` closure, `signInWithOAuth` with a `configure:`
closure for `ASWebAuthenticationSession`, `getOAuthSignInURL`, and two `linkIdentity` overloads.
v3 starts a flow with `signInWithOAuth(_:options:presenter:)`, `oauthSignInURL(_:options:)`, or
`linkIdentity(_:options:presenter:)`. The provider is unlabeled. `scopes`, `redirectTo` and
`queryParams` move into `OAuthOptions`; `scopes` is an array and `queryParams` is `queryItems`.
`presenter` shows the provider page. The default on Apple platforms is
`ASWebAuthenticationSessionPresenter`. On other platforms you must pass one.

```swift
// v2
try await supabase.auth.signInWithOAuth(
  provider: .github,
  redirectTo: URL(string: "myapp://login-callback"),
  scopes: "repo user",
  queryParams: [("access_type", "offline")]
)
// v3
try await supabase.auth.signInWithOAuth(
  .github,
  options: OAuthOptions(
    scopes: ["repo", "user"],
    redirectTo: URL(string: "myapp://login-callback"),
    queryItems: [URLQueryItem(name: "access_type", value: "offline")]
  )
)
```

## `configure:` and `launchFlow:` are presenters

The `configure:` closure that customized the `ASWebAuthenticationSession` is gone. Set
`prefersEphemeralWebBrowserSession` on the presenter. To control the session fully, or to open the
page another way, pass a `ClosurePresenter`. It replaces the `launchFlow:` closure: it gets the
URL and the callback scheme, and returns the callback URL.

```swift
// v2
try await supabase.auth.signInWithOAuth(provider: .github) { session in
  session.prefersEphemeralWebBrowserSession = true
}
try await supabase.auth.signInWithOAuth(provider: .github) { url in
  try await myBrowser.open(url)
}
// v3
try await supabase.auth.signInWithOAuth(
  .github,
  presenter: ASWebAuthenticationSessionPresenter(prefersEphemeralWebBrowserSession: true)
)
try await supabase.auth.signInWithOAuth(
  .github,
  presenter: ClosurePresenter { url, callbackScheme in
    try await myBrowser.open(url)
  }
)
```

To show the page with SwiftUI's `webAuthenticationSession` (iOS 16.4 and later), read it from the
environment and pass it through a `ClosurePresenter`. `callbackScheme` is `nil` when no redirect
URL is set, so give the system a scheme of your own to fall back on.

```swift
// v3
struct SignInView: View {
  @Environment(\.supabase) private var supabase
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession

  var body: some View {
    Button("Sign in with GitHub") {
      Task {
        try await supabase.auth.signInWithOAuth(
          .github,
          options: OAuthOptions(redirectTo: URL(string: "myapp://login-callback")),
          presenter: ClosurePresenter { [webAuthenticationSession] url, callbackScheme in
            try await webAuthenticationSession.authenticate(
              using: url,
              callbackURLScheme: callbackScheme ?? "myapp"
            )
          }
        )
      }
    }
  }
}
```

A user who cancels now gets `CancellationError`. Cancelling the task that awaits the call closes
the page and throws `CancellationError` too. On tvOS, the system cannot close the page, so the
call throws and the page stays until the user dismisses it. A new page cannot open before then.

An HTTPS `redirectTo`, a universal link, works on iOS 17.4, macOS 14.4, tvOS 17.4, visionOS 1.1,
and watchOS 10.4 and later. It needs the `webcredentials:` associated domain for the host of the
redirect URL. Only one page can be open at a time.

## `linkIdentity` shows the page and returns a session

The v2 `linkIdentity` overloads took a `launchURL` closure or opened the URL, and returned
nothing. v3 runs the whole flow with a presenter, like `signInWithOAuth`, and returns the new
`Session`. It emits `.userUpdated`. For your own flow, use `linkIdentityURL(_:options:)`.

```swift
// v2
try await supabase.auth.linkIdentity(provider: .google, redirectTo: callback) { url in
  UIApplication.shared.open(url)
}
let response = try await supabase.auth.getLinkIdentityURL(provider: .google)
open(response.url)
// v3
let session = try await supabase.auth.linkIdentity(
  .google, options: OAuthOptions(redirectTo: callback))
let flow = try await supabase.auth.linkIdentityURL(.google)
open(flow.url)
```

## `UserIdentity.id` is the identity UUID

In v2, `UserIdentity.id` was the user's ID at the provider, a `String`, and `identityId` was the
Supabase identity UUID. In v3, `id` is the identity UUID, the value that `unlinkIdentity(_:)`
sends. The provider's user ID is `providerUserID`. `Identifiable` uses `id`, so SwiftUI lists now
key on the identity UUID. Most uses stop compiling, because `id` is a `UUID`, not a `String`.
`"\(identity.id)"` still compiles and prints the UUID.

The v3 names follow what each value is, not the JSON keys of the Auth server. The server sends the
identity UUID as `identity_id` and the provider's user ID as `id`, and supabase-js keeps those
keys. So `id` means a different value in Swift than in the JSON and in supabase-js:

| Value | Swift v3 | JSON key and supabase-js | Swift v2 |
|---|---|---|---|
| Supabase identity UUID | `id: UUID` | `identity_id` | `identityId: UUID` |
| User's ID at the provider | `providerUserID: String` | `id` | `id: String` |
| UUID of the user | `userID: UUID` | `user_id` | `userId: UUID` |
| Email address of the identity | `email: String?` | `email` | none |

`email` is new in v3. The Auth server takes it from the provider, so it can differ from
`User.email`. It is `nil` when the server sends no email.

```swift
// v2
let providerUserID: String = identity.id
let identityID: UUID = identity.identityId
let isGoogle = identity.provider == "google"
let email = identity.identityData?["email"]?.stringValue
// v3
let providerUserID: String = identity.providerUserID
let identityID: UUID = identity.id
let isGoogle = identity.provider == .google
let email = identity.email
```

## `handleRedirect(_:)` replaces `session(from:)` and `handle(_:)`

`handleRedirect(_:)` takes the URL that opened your app. It returns `nil` when the URL is not an
auth redirect, and a `RedirectResult` otherwise: `.signedIn(Session, verification:)` or
`.emailChangePending(message:)`. `isAuthRedirect(_:)` checks a URL without handling it. Both
`AuthClient` and `SupabaseClient` have the method.

A URL is an auth redirect only when it opens a known callback: the configured `redirectTo`
(`SupabaseClient.Configuration.Auth.redirectTo` or Auth's `Configuration.redirectTo`) or the
`redirectTo` you passed when a flow started. Scheme, host, port, and path must match; a trailing
slash is ignored. Your own links, such as `myapp://invite?code=ABC`, return `nil`. With no callback
known, no URL is an auth redirect, so set the configured `redirectTo`. A callback that only a
per-call `redirectTo` names is known while its flow waits,
so an error redirect that arrives after the flow expired returns `nil`. A URL with a `message` item is an email-change redirect only when it also has the
`sb` marker. Auth servers before v2.186.0 do not send `sb`, so `handleRedirect(_:)` returns `nil`
for their email-change redirects.

```swift
// v2
.onOpenURL { url in supabase.handle(url) }
let session = try await supabase.auth.session(from: url)
// v3
.onOpenURL { url in
  Task { try await supabase.handleRedirect(url) }
}
if case .signedIn(let session, _)? = try await supabase.auth.handleRedirect(url) {
  show(session.user)
}
```

Use `isAuthRedirect(_:)` where several handlers share one URL entry point, for example to keep
your redirect away from another SDK's URL handler. It applies the same callback rule, and it is
`async` because it reads the pending flows from storage:

```swift
// v3
func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
  guard let url = contexts.first?.url else { return }
  Task {
    if await supabase.auth.isAuthRedirect(url) {
      try await supabase.handleRedirect(url)
    } else {
      ThirdPartySDK.open(url)
    }
  }
}
```

## Password recovery needs the redirect result or `.passwordRecovery`

A password reset link signs the user in, so a root view that switches on the session shows the
home screen. To show an "update password" screen, react to the link. `handleRedirect(_:)` returns
`.signedIn(_, verification: .recovery)` for it, and the client also emits `.passwordRecovery`. With
PKCE, which v3 always uses, the event fires too; v2 emitted it only in the implicit flow. The event
also covers `verifyOTP` with type `.recovery`, which has no redirect URL. `verification` is an
`EmailOTPType?`, and it is `nil` for an OAuth sign-in.

```swift
// v2
for await (event, _) in supabase.auth.authStateChanges where event == .passwordRecovery {
  isPasswordRecovery = true
}
// v3
.onOpenURL { url in
  Task {
    if case .signedIn(_, verification: .recovery)? = try await supabase.handleRedirect(url) {
      isPasswordRecovery = true
    }
  }
}
.task {
  for await change in supabase.auth.events() where change.event == .passwordRecovery {
    isPasswordRecovery = true
  }
}
```

Handle each URL in one place. `handleRedirect(_:)` returns the first result when it sees the same
code or token again, so a second handler gets the same result and sends no request. It remembers
only the last few redirects of the running process, so do not rely on it across launches.

## `flowType` is removed

v3 always uses PKCE for the flows it starts, and `handleRedirect(_:)` reads the flow from the URL,
so email links and implicit tokens still work. Remove `flowType:` from `AuthClient`,
`AuthClient.Configuration` and `SupabaseClientOptions.AuthOptions`.

```swift
// v2
let options = SupabaseClientOptions(auth: .init(flowType: .pkce))
// v3
let configuration = SupabaseClient.Configuration(auth: .init())
```

## `oauthSignInURL` returns an `OAuthFlow`

`oauthSignInURL` and `linkIdentityURL` are `async` and return an `OAuthFlow`: the `url` to open
and the `id` of the flow they started. Pass the ID back to `exchangeCodeForSession` when more than
one flow can be pending.

```swift
// v2
let url = try supabase.auth.getOAuthSignInURL(provider: .github)
let session = try await supabase.auth.exchangeCodeForSession(authCode: code)
// v3
let flow = try await supabase.auth.oauthSignInURL(.github)
let session = try await supabase.auth.exchangeCodeForSession(code, flowID: flow.id)
```

## `AuthError` is a struct

`AuthError` is a struct with `kind`, `message`, `code`, `weakPasswordReasons`, `oauthError`,
`response` and `underlyingError`. Match on `kind` and `code` instead of enum cases:
`catch AuthError.Code.invalidCredentials` and `catch AuthError.Kind.sessionMissing` compile.
`isRetryable` says whether to send the request again. `AuthError` is no longer `Equatable`.

The top-level `ErrorCode` is now `AuthError.Code`, and `errorCode` is now `code`. `code` is
optional: it is `nil` when the server sent no code, such as for an OAuth-style response, a body
that is not JSON, `AuthError.sessionMissing`, or a local JWT check. There is no `.unknown`
placeholder. Replace `error.errorCode == .unknown` with `error.code == nil`. Build a code from a
string literal or with `init(rawValue:)`; `ErrorCode("x")` no longer compiles.

Three errors no longer carry a code that the SDK made up. Match on `kind` for them instead:

| Before | Now |
| --- | --- |
| `AuthError.sessionMissing` with `.sessionNotFound` | `kind == .sessionMissing`, `code == nil` |
| A local JWT verification failure with `.invalidJWT` | `kind == .jwtVerificationFailed`, `code == nil` |
| A non-JSON error body, such as a proxy's HTML page, with `.unexpectedFailure` | `kind == .server`, `code == nil`; read `response?.status` |

`catch AuthError.Code.sessionNotFound`, `.invalidJWT` and `.unexpectedFailure` now match only when
GoTrue sent that code.

| v2 | v3 |
| --- | --- |
| `catch AuthError.sessionMissing`, `AuthError.sessionNotFound` | `catch AuthError.Kind.sessionMissing` (nothing stored) or `catch AuthError.Kind.sessionInvalidated` (the server rejected the session) |
| `.api(message, errorCode, underlyingData, underlyingResponse)`, `AuthError.APIError` | `error.kind == .server`; `error.code`, `error.response?.status`, `error.response?.body`. The kind is `.sessionInvalidated` for the codes that end a session, and `.oauthFlowFailed` for `flow_state_not_found`, `flow_state_expired` and `bad_code_verifier` |
| `.weakPassword(message, reasons)` | `error.code == .weakPassword`; `error.weakPasswordReasons` |
| `ErrorCode`, `error.errorCode`, `ErrorCode("x")`, `ErrorCode.unknown` | `AuthError.Code`, `error.code` (optional), `"x"` or `AuthError.Code(rawValue: "x")`, `nil` |
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
  print(error.response?.status.code ?? 0, error.code?.rawValue ?? "", error.message)
} catch AuthError.Kind.sessionMissing, AuthError.Kind.sessionInvalidated {
  showLogin()
}
```

`throw AuthError.sessionMissing` still compiles. `signInWithOAuth` now throws `.oauthFlowFailed`
when it has no redirect URL, where v2 trapped.

## MFA methods take arguments

The `params:` structs are gone. Each method takes its arguments directly, and enrollment has one
method per factor type, which returns that type's data.

```swift
// v2
let enrolled = try await supabase.auth.mfa.enroll(params: .totp(friendlyName: "Phone"))
showQRCode(enrolled.totp!.qrCode)
try await supabase.auth.mfa.challengeAndVerify(
  params: MFAChallengeAndVerifyParams(factorId: enrolled.id, code: code))
try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: enrolled.id))
// v3
let enrolled = try await supabase.auth.mfa.enrollTOTP(friendlyName: "Phone")
showQRCode(enrolled.qrCode)
try await supabase.auth.mfa.challengeAndVerify(factorID: enrolled.id, code: code)
try await supabase.auth.mfa.unenroll(factorID: enrolled.id)
```

## `listFactors()` is `factors()`

`factors()` fetches the user from the server on each call; v2 read the stored user. It splits the
factors by status, not by type. Filter on `factorType` for one type.

```swift
// v2
let totp = try await supabase.auth.mfa.listFactors().totp
// v3
let totp = try await supabase.auth.mfa.factors().verified.filter { $0.factorType == .totp }
```

## `getAuthenticatorAssuranceLevel()` is `assuranceLevel()`

With no session, `assuranceLevel()` throws an error of kind `.sessionMissing`. v2 returned `nil`
levels. It also throws an error of kind `.decoding` when the access token is not a JWT. Like
`factors()`, it fetches the user from the server, so `nextLevel` sees factors enrolled on other
devices; v2 read the stored user.

```swift
// v2
let aal = try await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
if aal.currentLevel == nil { showSignIn() }
// v3
do {
  let aal = try await supabase.auth.mfa.assuranceLevel()
  if aal.nextLevel != aal.currentLevel { showMFAPrompt() }
} catch let error as AuthError where error.kind == .sessionMissing {
  showSignIn()
}
```

## Sign in with an ID token takes a `Nonce`

`signInWithIDToken(_:)` takes `IDTokenCredentials`. v3 adds `Nonce` to tie the token to one
attempt. Generate one for each attempt, send `hashed` to the provider, and pass `raw` to the
server. Apple's `SignInWithAppleButton` uses `request.nonce`. `linkIdentity(idToken:)` takes the
same credentials.

```swift
// v2
SignInWithAppleButton { request in
  request.requestedScopes = [.email, .fullName]
} onCompletion: { result in
  // ...
  try await supabase.auth.signInWithIdToken(
    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken))
}
// v3
@State private var nonce = Nonce.generate()

SignInWithAppleButton { request in
  nonce = Nonce.generate()
  request.requestedScopes = [.email, .fullName]
  request.nonce = nonce.hashed
} onCompletion: { result in
  // ...
  try await supabase.auth.signInWithIDToken(
    IDTokenCredentials(provider: .apple, idToken: idToken, nonce: nonce.raw))
}
```

## `signUp` returns `SignUpResult`

`signUp(email:)` and `signUp(phone:)` return `SignUpResult` instead of `AuthResponse`. Its cases
say whether the user is signed in: `.signedIn(Session)` or `.confirmationRequired(User)`. The
`session` and `user` properties stay. The metadata, redirect URL, channel, and captcha token move
into `SignUpOptions`, and `data:` is `userMetadata:`. `signUp` is no longer
`@discardableResult`, so a call that ignores the result warns. Write `_ =` if you do not need it.

```swift
// v2
let response = try await supabase.auth.signUp(
  email: email, password: password, data: ["name": .string(name)], captchaToken: token)
if response.session == nil { showCheckYourInbox() }
// v3
let result = try await supabase.auth.signUp(
  email: email, password: password,
  options: SignUpOptions(userMetadata: ["name": .string(name)], captchaToken: token))
switch result {
case .signedIn(let session): showHome(for: session.user)
case .confirmationRequired: showCheckYourInbox()
}
```

## `signInWithOTP` takes `EmailOTPOptions` or `PhoneOTPOptions`

`shouldCreateUser`, the metadata, and the captcha token move into the options type, and `data:` is
`userMetadata:`. Only `EmailOTPOptions` has `redirectTo`, and only `PhoneOTPOptions` has `channel`.
Phone sign-in returns the `MessageID?` of the SMS, so you can track delivery.

```swift
// v2
try await supabase.auth.signInWithOTP(
  email: email, redirectTo: callback, shouldCreateUser: false, captchaToken: token)
try await supabase.auth.signInWithOTP(phone: phone, channel: .whatsapp)
// v3
try await supabase.auth.signInWithOTP(
  email: email,
  options: EmailOTPOptions(shouldCreateUser: false, redirectTo: callback, captchaToken: token))
let messageID = try await supabase.auth.signInWithOTP(
  phone: phone, options: PhoneOTPOptions(channel: .whatsapp))
```

## `resend` and `resetPassword` take options

The redirect URL and the captcha token move into `ResendEmailOptions`, `ResendPhoneOptions`, and
`ResetPasswordOptions`. `emailRedirectTo:` is `redirectTo:`.

```swift
// v2
try await supabase.auth.resend(
  email: email, type: .signup, emailRedirectTo: callback, captchaToken: token)
try await supabase.auth.resetPasswordForEmail(email, redirectTo: callback)
// v3
try await supabase.auth.resend(
  email: email, type: .signup,
  options: ResendEmailOptions(redirectTo: callback, captchaToken: token))
try await supabase.auth.resetPassword(
  email: email, options: ResetPasswordOptions(redirectTo: callback))
```

## `verifyOTP` returns `VerifyOTPResult` or a `Session`

`verifyOTP(email:)` and `verifyOTP(tokenHash:)` return `VerifyOTPResult` instead of v2's
`AuthResponse`: `.signedIn(Session)`, or `.emailChangePending(message:)` for the first confirmation
of a secure email change, which signs no one in. `verifyOTP(phone:)` returns the `Session`.

```swift
// v2
let response = try await supabase.auth.verifyOTP(tokenHash: hash, type: .emailChange)
let email = response.user.email
// v3
switch try await supabase.auth.verifyOTP(tokenHash: hash, type: .emailChange) {
case .signedIn(let session):
  let email = session.user.email
case .emailChangePending(let message):
  print(message)
}
let session = try await supabase.auth.verifyOTP(phone: phone, token: code, type: .sms)
```

## `signInWithSSO` shows the page and returns a session

v2 returned an `SSOResponse` with the URL and left the browser to the app. v3 takes an `SSOTarget`
(`.domain(String)` or `.providerID(UUID)`), shows the identity provider page with a presenter, like
`signInWithOAuth`, and returns the `Session`. It emits `.signedIn`. For your own flow, use
`ssoSignInURL(_:options:)`, which returns an `OAuthFlow`.

```swift
// v2
let response = try await supabase.auth.signInWithSSO(domain: "example.com", redirectTo: callback)
await UIApplication.shared.open(response.url)
// v3
let session = try await supabase.auth.signInWithSSO(
  .domain("example.com"), options: SSOOptions(redirectTo: callback))
let flow = try await supabase.auth.ssoSignInURL(
  .providerID(UUID(uuidString: providerID)!))
```

## `Session` times are `Date` and `Duration`

`expiresAt` is a `Date` and `expiresIn` is a `Duration`, not `TimeInterval`s. A new `receivedAt`
is the time the client received the session. The client judges expiry from it, so
`isExpired(at:leeway:)` replaces the `isExpired` property and takes the clock and the margin.
A `Session` decoded without `receivedAt`, as every session that v2 stored, counts as received at
`expiresAt - expiresIn`. The stored session format does not change.

```swift
// v2
let remaining = session.expiresAt - Date().timeIntervalSince1970
let needsRefresh = session.isExpired
// v3
let remaining = session.expiresAt.timeIntervalSinceNow
let needsRefresh = session.isExpired(leeway: .seconds(60))
```

## `JWTClaimsResponse` and `JWTClaims` are `VerifiedClaims`

`claims(options:)` and `claims(jwt:options:)` return `VerifiedClaims` instead of
`JWTClaimsResponse`. The claims are top-level properties with full names, and `header` and
`signature` stay. `sub` and `exp` are required, so `subject` and `expiresAt` are not optional,
and a token without them fails verification. `aud` is always a `[String]`, `exp` and `iat` are `Date`s, `aal` is an
`AuthenticatorAssuranceLevel`, and `AudienceClaim` is gone. `session_id`, `is_anonymous`, `app_metadata`, `user_metadata`, `nbf` (as the `Date` `notBefore`), and the `amr` entries fill
their typed properties. `jti` and every other claim are in `additionalClaims`.

```swift
// v2
let response = try await supabase.auth.getClaims()
let userID = response.claims.sub
let sessionID = response.claims.sessionId
let expiresAt = response.claims.exp.map(Date.init(timeIntervalSince1970:))
// v3
let claims = try await supabase.auth.claims()
let userID = claims.subject
let sessionID = claims.sessionID
let expiresAt = claims.expiresAt
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
for await change in supabase.auth.events() {
  if change.event == .initialSession, let session = change.session, !session.isExpired() {
    signIn(user: session.user)
  }
}
```

## `authStateChanges` and `onAuthStateChange(_:)` are `events()`

`events()` returns one `AsyncStream<AuthChange>` per call. It is registered when the call returns,
so it loses no change, and it finishes when your task is cancelled or the client is released.
`AuthChange` has `event`, `session`, `status` (an `AuthStatus`), and `signOutReason`, which tells
`.userInitiated` from `.sessionExpired`, `.sessionRevoked`, and `.sessionMissing`. For the state
without a stream, read `auth.status`, or `await auth.initialization()` to wait until storage is
read. `AuthStateChangeListener`, `AuthStateChangeListenerRegistration` and `ObservationToken` are
removed.

```swift
// v2
for await (event, session) in supabase.auth.authStateChanges {
  if event == .signedOut { showSignIn() }
}
let subscription = await supabase.auth.onAuthStateChange { event, session in
  print(event, session?.user.id as Any)
}
subscription.remove()
// v3
for await change in supabase.auth.events() {
  if change.event == .signedOut { showSignIn() }
}
let task = Task {
  for await change in supabase.auth.events() {
    print(change.event, change.session?.user.id as Any)
  }
}
task.cancel()
```

## `AuthModel` replaces a hand-written observable wrapper

`AuthClient` is `Sendable`, not `@Observable`. Many v2 apps wrapped `authStateChanges` in their own
`@Observable` class. On iOS 17, macOS 14, tvOS 17, watchOS 10, and visionOS 1 or later, use
`AuthModel` instead. It reads `status` (`.loading`, `.signedOut(SignOutReason?)`,
`.signedIn(Session)`) and has `session`, `user`, and `isLoading`. It keeps only the status, so consume `events()` too for an
event such as `.passwordRecovery`. The model does not retain the client; keep the client alive.

The SDK ships no SwiftUI environment key. Declare one with `@Entry` to give views the client. Use the same client as the model.

```swift
// v2
@Observable @MainActor final class AuthController {
  var session: Session?
  init() {
    Task {
      for await (_, session) in supabase.auth.authStateChanges { self.session = session }
    }
  }
}
// v3
let supabaseClient = try! SupabaseClient(supabaseURL: url, supabaseKey: key)

extension EnvironmentValues {
  @Entry var supabase = supabaseClient
}

@main struct MyApp: App {
  @State private var auth = AuthModel(client: supabaseClient.auth)

  var body: some Scene {
    WindowGroup { RootView().environment(auth) }
  }
}

struct RootView: View {
  @Environment(AuthModel.self) private var auth

  var body: some View {
    switch auth.status {
    case .loading: ProgressView()
    case .signedOut: SignInView()
    case .signedIn: HomeView()
    }
  }
}
```

`auth.user?.id` reads the signed-in user without an `await`. The v2 property `try await
supabase.auth.session` is the method `try await supabase.auth.session()` on the client, not on the
model; use it when you need a session that is not expired. For iOS 16, see "Support iOS 16" in the DocC article "Observing auth state in
SwiftUI".

## `didChangeAuthStateNotification` is removed

`AuthClient.didChangeAuthStateNotification`, `authChangeEventInfoKey`, and
`authChangeSessionInfoKey` are removed. The notification was posted with `object: nil`, so two
clients could not be told apart. Use `events()` on the client you care about.

```swift
// v2
NotificationCenter.default.addObserver(
  forName: AuthClient.didChangeAuthStateNotification, object: nil, queue: .main
) { notification in
  let event = notification.userInfo?[AuthClient.authChangeEventInfoKey] as? AuthChangeEvent
  print(event as Any)
}
// v3
Task {
  for await change in supabase.auth.events() {
    print(change.event)
  }
}
```

## `AuthClient` is created from a `Configuration`

`AuthClient.init(configuration:)` is the only initializer. `url` and `storageKey` are required,
`headers` is `HTTPFields`, and every property is a `var`. The client adds `X-Client-Info` unless
`headers` sets it. `SupabaseClient` fills all of this in for you.

```swift
// v2
let auth = AuthClient(
  url: url,
  headers: ["apikey": key],
  redirectToURL: redirect,
  localStorage: KeychainLocalStorage()
)
// v3
var configuration = AuthClient.Configuration(url: url, storageKey: "sb-project-auth-token")
configuration.headers[HTTPField.Name("apikey")!] = key
configuration.redirectTo = redirect
let auth = try AuthClient(configuration: configuration)
```

## Custom `encoder` and `decoder` are removed

`AuthClient` and `AuthClient.Configuration` no longer take `encoder:` or `decoder:`, and
`SupabaseClientOptions.AuthOptions` no longer has them. Auth always uses its own JSON coders.

```swift
// v2
let auth = AuthClient(url: url, localStorage: storage, encoder: myEncoder, decoder: myDecoder)
// v3
let auth = try AuthClient(configuration: .init(url: url, storageKey: "my-key", storage: storage))
```

## `autoRefreshToken` is `autoRefresh`

`autoRefreshToken: true` is `autoRefresh: .automatic`, the default. `autoRefreshToken: false` is
`autoRefresh: .manual`: `session()` still refreshes an expired session, and nothing refreshes it
ahead of time. The new `.disabled` never refreshes on its own, and `session()` throws an
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
let supabase = try SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  configuration: .init(auth: .init(autoRefresh: .manual))
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

## `AuthLocalStorage` is `AuthStorage`

`AuthStorage` is `async`, and `save(_:key:)` takes the bytes first. `KeychainLocalStorage` is
`KeychainStorage`. `WinCredLocalStorage` and `WinCredLocalStorageError` are removed. On Windows,
as on Linux and Android, the default storage keeps the session in memory, so the user must sign in
again after the app exits. The v2 type could not read back what it wrote, so no stored session is
lost. To persist the session, pass your own `AuthStorage`.

```swift
// v2 (Windows)
struct MyLocalStorage: AuthLocalStorage {
  func store(key: String, value: Data) throws { /* ... */ }
  func retrieve(key: String) throws -> Data? { /* return nil when missing */ }
  func remove(key: String) throws { /* ... */ }
}
// v3 (Windows)
struct MyStorage: AuthStorage {
  func save(_ data: Data, key: String) async throws { /* ... */ }
  func load(key: String) async throws -> Data? { /* return nil when missing */ }
  func remove(key: String) async throws { /* ... */ }
}
let supabase = try! SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  configuration: .init(auth: .init(storage: MyStorage()))
)
```

On macOS, `KeychainStorage()` uses the data-protection Keychain, which removes the Keychain
consent prompt and needs a provisioning profile with Keychain entitlements. It moves a session
from the file-based Keychain on the first load. On macOS, the default storage of a client keeps
the file-based Keychain, as v2 did.

## Experimental APIs

Passkeys and WebAuthn MFA are `@_spi(Experimental)`. Import them with
`@_spi(Experimental) import Supabase` (or `import Auth`). They may change in any release.

In v3, first-factor passkey calls move to `auth.passkeys` and admin calls to
`AuthAdminClient.passkeys`.
Challenge IDs are `UUID`, and the presentation anchor is optional; `nil` uses the app's key
window. A user who cancels the passkey sheet now gets `CancellationError`.
`mfa.verifyWebAuthn` only steps up with a verified factor; for an unverified one it throws an
`AuthError` of kind `mfaFactorNotVerified` before it shows the sheet.

| v2 | v3 |
| --- | --- |
| `auth.signInWithPasskey(presentationAnchor:)` | `auth.passkeys.signIn(anchor:)` |
| `auth.registerPasskey(presentationAnchor:)` | `auth.passkeys.register(anchor:)` |
| `auth.getPasskeyRegistrationOptions()` | `auth.passkeys.registrationOptions()` |
| `auth.verifyPasskeyRegistration(challengeId:credentialResponse:)` | `auth.passkeys.verifyRegistration(challengeID:credential:)` |
| `auth.getPasskeyAuthenticationOptions()` | `auth.passkeys.authenticationOptions()` |
| `auth.verifyPasskeyAuthentication(challengeId:credentialResponse:)` | `auth.passkeys.verifyAuthentication(challengeID:credential:)` |
| `auth.listPasskeys()` | `auth.passkeys.list()` |
| `auth.renamePasskey(id:friendlyName:)` | `auth.passkeys.rename(id:friendlyName:)` |
| `auth.deletePasskey(id:)` | `auth.passkeys.delete(id:)` |
| `PasskeyRegistrationOptions.challengeId: String` | `challengeID: UUID` (same for `PasskeyAuthenticationOptions`) |
| `auth.mfa.enrollWebAuthnFactor(friendlyName:presentationAnchor:)` | `auth.mfa.enrollWebAuthn(friendlyName:anchor:)` |
| `auth.mfa.verifyWebAuthnFactor(factorId:presentationAnchor:)` | `auth.mfa.verifyWebAuthn(factorID:anchor:)` |
| `mfa.enroll(params: .webAuthn(friendlyName:))` | `mfa.enrollWebAuthnFactor(friendlyName:)`, which returns the factor ID |
| `mfa.challenge(params: MFAChallengeParams(factorId:webAuthn:))` | `mfa.challenge(factorID:webAuthn:)` |
| `mfa.verify(params: MFAVerifyParams(factorId:challengeId:credentialResponse:))` | `mfa.verify(factorID:challengeID:type:credentialResponse:)` |
| `admin.listPasskeys(userId:)` | `admin.passkeys.list(forUser:)` |
| `admin.deletePasskey(userId:passkeyId:)` | `admin.passkeys.delete(id:forUser:)` |
| `signInWithPasskey` and `verifyPasskeyAuthentication` return `AuthResponse` | They return `Session` |
