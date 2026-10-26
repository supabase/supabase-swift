# Auth v3 migration

This file covers the changes to `AuthClient`, sessions, MFA, OAuth, `AuthError` and local storage
from v2 to v3. See [the v3 migration overview](../../../V3_MIGRATION.md) for steps that apply to
every module.

> [!NOTE]
> The Auth API is still being reworked for v3. It may change before v3.0.0.

## Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **Initial session can be expired.** `.initialSession` now fires at once with the stored session,
  and an expired session refreshes in the background. Check `session.isExpired` in handlers that
  switch on `.initialSession`.
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
  means only that no session is stored. Search for `.sessionMissing` and also handle
  `.sessionInvalidated` where you send the user back to sign-in.
- **No email or phone is `nil`.** `User.email` and `User.phone` are `nil`, not `""`, when the
  user has none. Search for `email == ""`, `phone == ""`, `email?.isEmpty`, and `phone?.isEmpty`.
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
| `AuthClient.Configuration.autoRefreshToken`, `.defaultAutoRefreshToken` | `.automaticallyRefreshesToken`, `.defaultAutomaticallyRefreshesToken` |
| `SupabaseClientOptions.AuthOptions.autoRefreshToken` | `.automaticallyRefreshesToken` |
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

## `AuthClient` is not an actor

Remove `isolated AuthClient` parameters and `assumeIsolated` calls. `startAutoRefresh()` and
`stopAutoRefresh()` are synchronous now; drop the `await`.

```swift
// v2
func inspect(_ auth: isolated AuthClient) { print(auth.currentUser?.email ?? "") }
await supabase.auth.startAutoRefresh()
// v3
func inspect(_ auth: AuthClient) { print(auth.currentUser?.email ?? "") }
supabase.auth.startAutoRefresh()
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
