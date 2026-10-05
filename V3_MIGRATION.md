# V3 Migration Guide

This document describes the breaking changes you need to be aware of when upgrading to v3 of the
Supabase Swift SDK, together with the steps required to migrate your code. All modules
(`Auth`, `Storage`, `Realtime`, `PostgREST`, `Functions`, `Supabase`) are covered here.

> [!NOTE]
> v3 has not been released yet. This document is updated as breaking changes land on `main`, so
> treat it as the running list rather than the final one.

## Minimum toolchain is now Xcode 26.0 / Swift 6.2

The package now requires Xcode 26.0 or later and Swift 6.2 or later (`swift-tools-version:6.2`).
The previous floor was Xcode 16.4 / Swift 6.1.

The [support policy](README.md#support-policy) ties the minimum Xcode to the versions eligible for
App Store submission. Since April 28, 2026, App Store Connect only accepts uploads built with
Xcode 26 or later, so Xcode 16.x is already out of policy. Dropping it is not a breaking change
under that policy, but it is listed here because it changes what you need installed to build v3.

### Migration

Update to Xcode 26.0 or later. No source changes are required.

## `verifyOTP` now returns `VerifyOTPResponse` instead of `AuthResponse`

`verifyOTP` and its overloads return a new `VerifyOTPResponse` type instead of `AuthResponse`.

GoTrue's `/verify` endpoint returns a body with only `{ msg, code }` for the first of the two
confirmations required by a secure email change — a shape `AuthResponse` can't represent, since it
only ever holds a `Session` or a `User`. That made `verifyOTP(type: .emailChange)` throw a
`DecodingError` instead of completing successfully. `AuthResponse` is also the return type of
`signUp` and the Passkey methods, neither of which can ever produce that shape, so growing it to
fit `verifyOTP` would have meant every caller of those unrelated methods handling a case only one
specific call can trigger.

`VerifyOTPResponse` only has the two shapes `verifyOTP` can actually return:

```swift
public enum VerifyOTPResponse {
  case session(Session)
  case emailChangeConfirmationPending(EmailChangeConfirmation)
}
```

`EmailChangeConfirmation` carries the `message`/`code` GoTrue sends for that first confirmation.
There's no bare-`User` case here — succeeding at `/verify` always means either a session was
issued or the other email still needs to confirm; unlike `signUp`, it can never leave you with a
user and no session.

This is a compile error, not a silent behavior change: the return type itself changed, so every
call site using the result needs updating.

```swift
// Before
let response: AuthResponse = try await client.verifyOTP(tokenHash: hash, type: .emailChange)
let email = response.user.email

// After
let response: VerifyOTPResponse = try await client.verifyOTP(tokenHash: hash, type: .emailChange)
switch response {
case .session(let session):
  let email = session.user.email
case .emailChangeConfirmationPending(let confirmation):
  print("\(confirmation.message) (code: \(confirmation.code))")
}
```

`AuthResponse` itself is unchanged: `signUp` and the Passkey methods still return it, and `user` is
still non-optional there, since neither endpoint can produce the confirmation-pending shape.

## `emitLocalSessionAsInitialSession` removed — the locally stored session is now always emitted as the initial session

`AuthClient.Configuration.emitLocalSessionAsInitialSession` and the matching parameter on
`AuthClient.init`/`SupabaseClientOptions.AuthOptions.init` are removed. The behavior it used to gate
behind `true` is now the only behavior.

Previously, the `.initialSession` auth state change event was emitted only after the SDK tried to
refresh the locally stored session, silently swallowing the difference between a session that was
merely expired (refreshable) and one whose refresh token was actually invalid (e.g. revoked or
already used) — both surfaced the same way to listeners, and every launch paid the cost of a
network round-trip before `.initialSession` fired at all. `.initialSession` now always fires
immediately with whatever session is stored locally, and a best-effort refresh happens in the
background if it's expired. See
[#822](https://github.com/supabase/supabase-swift/pull/822) for the original discussion.

This is a compile error for anyone passing `emitLocalSessionAsInitialSession:` explicitly — the
parameter no longer exists. It's also a silent behavior change for everyone else: search your
codebase for `onAuthStateChange`/`authStateChanges` handlers that switch on `.initialSession` and
assume the session they receive is always valid. Since the initial session may now be expired,
check `session.isExpired` yourself:

```swift
// Before
for await (event, session) in client.auth.authStateChanges {
  if event == .initialSession, let session {
    signIn(user: session.user)
  }
}

// After
for await (event, session) in client.auth.authStateChanges {
  if event == .initialSession, let session, !session.isExpired {
    signIn(user: session.user)
  }
}
```

There's no escape hatch back to the old behavior — the SDK no longer performs a blocking refresh
before the initial session fires.

## Several public types narrowed from `Codable` to `Decodable` or `Encodable`

Many public types only ever get used in one direction — either decoded from a server response, or
encoded into a request body — but declared full `Codable` anyway. That's now narrowed to match
actual usage, and a couple of hand-rolled coders that only existed for the unused direction were
deleted along with it.

**Narrowed to `Decodable`-only** (no longer `Encodable`): `AuthResponse`, `SSOResponse`,
`OAuthClient`, `OAuthClientType`, `OAuthClientRegistrationType`, `OAuthAuthorizationClient`,
`OAuthAuthorizationUser`, `OAuthAuthorizationDetails`, `OAuthRedirect`, `OAuthGrant`, `JWK`, `JWKS`,
`JWTHeader`, `JWTClaims`, `AudienceClaim`, `PasskeyListItem` (Auth); `FileObject`, `Bucket`,
`VectorBucket`, `VectorIndex`, `VectorIndexSummary`, `VectorMatch` (Storage); `Column`, `PresenceV2`
(Realtime); `PostgrestError` (shared).

**No longer conform to `Codable` at all** (never encoded or decoded through Codable machinery in
the first place): `OAuthResponse`, `Provider` (Auth).

**Narrowed to `Encodable`-only** (no longer `Decodable`): `OpenIDConnectCredentials`,
`OpenIDConnectCredentials.Provider`, `AuthMetaSecurity`, `Web3Credentials`, `Web3Chain`,
`UserAttributes`, `MessagingChannel` (Auth); `ReplayOption`, `BroadcastJoinConfig`,
`PresenceJoinConfig` (Realtime); `VectorEntry`, `ResizeMode`, `ImageFormat`, `SortOrder` (Storage).

If you were relying on encoding one of the `Decodable`-only types (or decoding one of the
`Encodable`-only types) yourself — e.g. to persist it to disk or pass it through your own
`Codable`-based pipeline — wrap it in your own type instead:

```swift
// Before: encoding a response type directly
let data = try JSONEncoder().encode(oauthClient)

// After: wrap it in your own Codable type if you need to round-trip it
struct MyOAuthClientCache: Codable {
  let clientId: UUID
  let clientName: String
  // ...the fields you actually need to persist
}
```

The mirror case — decoding an `Encodable`-only type from stored JSON instead of constructing it
directly — needs the same wrapper:

```swift
// Before: decoding a request type from stored JSON
let credentials = try JSONDecoder().decode(OpenIDConnectCredentials.self, from: data)

// After: decode into your own Codable type, then construct the request type from it
struct MyStoredCredentials: Codable {
  let provider: String
  let idToken: String
}
let stored = try JSONDecoder().decode(MyStoredCredentials.self, from: data)
let credentials = OpenIDConnectCredentials(provider: .init(rawValue: stored.provider)!, idToken: stored.idToken)
```

## All previously-deprecated APIs have been removed

Every API that carried an `@available(*, deprecated, ...)` annotation ahead of v3 has now been
removed outright. If your project still built without deprecation warnings, none of this affects
you. If it built with warnings, each warning's replacement (already given in the deprecation
message) is now mandatory. This is a compile error everywhere: the old symbols no longer exist.

### Auth

| Before | After |
| --- | --- |
| `GoTrueClient` | `AuthClient` |
| `GoTrueMFA` | `AuthMFA` |
| `GoTrueLocalStorage` | `AuthLocalStorage` |
| `GoTrueMetaSecurity` | `AuthMetaSecurity` |
| `GoTrueError` | `AuthError` |
| `JSONEncoder.goTrue` | `AuthClient.Configuration.jsonEncoder` |
| `JSONDecoder.goTrue` | `AuthClient.Configuration.jsonDecoder` |
| `MFAEnrollParams` | `MFATotpEnrollParams` or `MFAPhoneEnrollParams` |
| `AuthAdmin.deleteUser(id: String, shouldSoftDelete:)` | `AuthAdmin.deleteUser(id: UUID, shouldSoftDelete:)` |
| `AuthError.sessionNotFound` | `AuthError.sessionMissing` |
| `AuthError.pkce(_:)` / `AuthError.PKCEFailureReason` | `AuthError` with `kind == .oauthFlowFailed` |
| `AuthError.invalidImplicitGrantFlowURL` | `AuthError` with `kind == .oauthFlowFailed` |
| `AuthError.api(_ error: APIError)` / `AuthError.APIError` | `AuthError` with `kind == .server`; `errorCode` and `response` carry the details |
| `UserAttributes.emailChangeToken` | *(removed, no replacement — was unused by GoTrue)* |

Also removed, with no replacement, because they no longer represent something GoTrue can throw:
`AuthError.missingExpClaim`, `AuthError.malformedJWT`, `AuthError.missingURL`.

`AuthError.invalidRedirectScheme` was removed on the same grounds, but has since come back as
`AuthError.Kind.oauthFlowFailed` — the condition is client-side, not something GoTrue throws.
See "`AuthError` gains `Kind.oauthFlowFailed`" below.

`UserCredentials` was deprecated ("access will be removed on the next major release") and is now
internal — it was only ever used by `AuthClient` itself to encode the request body for
`signIn(email:password:)`/`signIn(phone:password:)`/session refresh, never something callers were
meant to construct directly. Those `signIn` methods are unaffected; only direct use of the
`UserCredentials` type itself no longer compiles.

Customizing Auth's JSON encoding/decoding is no longer supported at all: the
`AuthClient.Configuration.init`/`AuthClient.init` overloads taking `encoder:`/`decoder:`
parameters, `AuthClient.Configuration.encoder`/`.decoder`, and
`SupabaseClientOptions.AuthOptions.encoder`/`.decoder` have all been removed. Auth always uses its
internal JSON encoder/decoder now.

```swift
// Before
let client = AuthClient(
  url: url, localStorage: storage, encoder: myEncoder, decoder: myDecoder,
  fetch: { try await URLSession.shared.data(for: $0) }
)

// After
let client = AuthClient(url: url, localStorage: storage)
```

### PostgREST

| Before | After |
| --- | --- |
| `URLQueryRepresentable` | `PostgrestFilterValue` |
| `PostgrestFilterValue.queryValue` | `PostgrestFilterValue.rawValue` |
| `.like(_:value:)` | `.like(_:pattern:)` |
| `.ilike(_:value:)` | `.ilike(_:pattern:)` |
| `.in(_:value:)` | `.in(_:values:)` |
| `.plfts(_:query:config:)` | `.textSearch(_:query:config:type: .plain)` |
| `.phfts(_:query:config:)` | `.textSearch(_:query:config:type: .phrase)` |
| `.wfts(_:query:config:)` | `.textSearch(_:query:config:type: .websearch)` |
| `.explain(...format: String)` | `.explain(...format: ExplainFormat)`, e.g. `format: .json` |

The `PostgrestClient.Configuration.init`/`PostgrestClient.init` overloads taking `encoder:`/
`decoder:` were also removed, for the same reason as Auth above — customizing PostgREST's JSON
codec is no longer supported.

```swift
// Before
try await client.from("users").select().ilike("email", value: "john%").execute()

// After
try await client.from("users").select().ilike("email", pattern: "john%").execute()
```

### Storage

| Before | After |
| --- | --- |
| `BucketOptions.public` / `init(public:...)` | `BucketOptions.isPublic` / `init(isPublic:...)` |
| `createSignedURL`/`createSignedURLs`/`getPublicURL(..., download: Bool)` | `download: DownloadBehavior?` (`.withOriginalName`, `.named("file.pdf")`) |
| `createSignedURLs(...) -> [URL]` | `createSignedURLs(...) -> [SignedURLResult]` |
| `upload`/`update`/`uploadToSignedURL(...) -> String` | the overloads returning `FileUploadResponse` / `SignedURLUploadResponse` |
| `SortBy.init(column:order: String?)` | `SortBy.init(column:order: SortOrder?)` |
| `TransformOptions.init(...resize: String?..., format: String?)` | `TransformOptions.init(...resize: ResizeMode?..., format: ImageFormat?)` |
| `JSONEncoder.defaultStorageEncoder` / `JSONDecoder.defaultStorageDecoder` | *(removed, no public replacement — was only ever the client's internal default)* |
| `StorageClientConfiguration.init(...encoder:decoder:session:...)` | `StorageClientConfiguration.init(...logger:...)` |
| `Storage.File` / `Storage.FormData` | *(removed — uploads no longer build a multipart form; see "Storage uploads send the raw file body" below)* |

```swift
// Before
let bucket = try await storage.createBucket("avatars", options: .init(public: true))
let url = try await storage.from("avatars").createSignedURL(path: "a.png", expiresIn: 60, download: true)

// After
let bucket = try await storage.createBucket("avatars", options: .init(isPublic: true))
let url = try await storage.from("avatars").createSignedURL(
  path: "a.png", expiresIn: 60, download: .withOriginalName
)
```

### Supabase

`SupabaseClient.database` and `SupabaseClient.realtime` have been removed.

```swift
// Before
try await supabase.database.from("users").select().execute()
supabase.realtime.connect()

// After
try await supabase.from("users").select().execute()
supabase.realtimeV2.connect()
```

### Realtime

The entire legacy v1 API has been removed: `RealtimeClient`, `RealtimeChannel`, `Presence`, and
their supporting types (`PhoenixTransport`, `Push`, `Delegated`, `HeartbeatTimer`, `TimeoutTimer`,
and the `Message` typealias). Use `RealtimeClientV2`, `RealtimeChannelV2`, and `PresenceV2` — see
[the RealtimeV2 migration guide](docs/migrations/RealtimeV2%20Migration%20Guide.md) for the full
v1-to-v2 walkthrough.

`RealtimeClientV2` and `RealtimeChannelV2` also had their own deprecated compatibility members
removed:

| Before | After |
| --- | --- |
| `RealtimeClientV2.subscriptions` | `RealtimeClientV2.channels` |
| `RealtimeClientV2.Configuration` | `RealtimeClientOptions` |
| `RealtimeClientV2.Status` | `RealtimeClientStatus` |
| `RealtimeClientV2.init(config:)` | `RealtimeClientV2.init(url:options:)` |
| `RealtimeClientV2.addChannel(_:)` | *(removed — the client tracks channels automatically)* |
| `RealtimeChannelV2.Subscription` | `RealtimeSubscription` |
| `RealtimeChannelV2.Status` | `RealtimeChannelStatus` |
| `RealtimeChannelV2.subscribe()` | `RealtimeChannelV2.subscribeWithError()` |
| `RealtimeChannelV2.updateAuth(jwt:)` | `RealtimeClientV2.setAuth(_:)` |
| `postgresChange(_:schema:table:filter: String?:select:)` | `postgresChange(_:schema:table:filter: RealtimePostgresFilter?:select:)` |
| `broadcast(event:) -> AsyncStream<JSONObject>` | `broadcastStream(event:)` |
| `RealtimeMessageV2.eventType` | inspect the raw event value in `RealtimeMessageV2.event` instead |
| `RealtimeMessageV2.EventType.tokenExpired` | now returned as `.system`; check the payload instead |

### Helpers

`ObservationToken.remove()` has been removed — use `.cancel()` instead. `PostgrestError.detail`
and `PostgrestError.init(detail:hint:code:message:)` have been removed — use `.details` and
`init(details:hint:code:message:)`.

## Logging: `SupabaseLogger` replaced with swift-log

`SupabaseLogger`, `SupabaseLogMessage`, `SupabaseLogLevel`, and `OSLogSupabaseLogger` are removed.
Every `logger:` parameter across `SupabaseClient`, `AuthClient`, `PostgrestClient`,
`SupabaseStorageClient`, `RealtimeClientOptions`, and `FunctionsClient` now takes a
[`Logging.Logger`](https://github.com/apple/swift-log) instead of a `SupabaseLogger`. The SDK had
been carrying its own logging protocol since before swift-log was a viable dependency for a
library this size; now that swift-log is the ecosystem standard, a bespoke protocol only meant
every consumer had to write an adapter to plug the SDK's logs into whatever logging backend
(OSLog, swift-log itself, a custom sink) their app already used. Taking `Logging.Logger` directly
removes that adapter entirely — any existing swift-log-based setup now works unmodified.

This is a compile error, not a silent behavior change: `logger:` parameters have a new type, so any
call site passing a `SupabaseLogger` conformance no longer compiles.

We don't re-export the `Logging` module, so constructing or spelling a `Logging.Logger` value in
your own app or package requires two things of your own target, same as any other transitive
dependency you want to use directly:

- an explicit `import Logging` in the file that constructs the `Logger`
- `swift-log` declared as an explicit dependency, e.g. in `Package.swift`:

  ```swift
  .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
  ```

  and on the relevant target:

  ```swift
  .product(name: "Logging", package: "swift-log"),
  ```

```swift
// Before
import Supabase

let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(global: .init(logger: MyCustomLogger()))
)

// After
import Logging
import Supabase

var logger = Logger(label: "myapp")
logger.logLevel = .debug
let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(global: .init(logger: logger))
)
```

**Default behavior changed.** Previously, omitting `logger:` meant fully silent output, in both
debug and release builds. Now, debug builds log warning-and-above to stderr by default, so you may
see new console output after upgrading even without passing a logger yourself; release builds
remain fully silent by default, matching the old behavior. To silence the debug-build default,
pass a `Logger` backed by `SwiftLogNoOpLogHandler` (add `import Logging` to this file):

```swift
logger: Logger(label: "myapp") { _ in SwiftLogNoOpLogHandler() }
```

**OSLog parity.** `OSLogSupabaseLogger`'s zero-config OSLog/Console.app integration has no
replacement shipped by the SDK. Implement your own `LogHandler` conforming type that wraps an
`os.Logger` and forwards each `Logging.Logger.Level` to the matching OSLog level, then install it
as the backing handler for a `Logger` (add `import Logging` to this file):

```swift
logger: Logger(label: "myapp") { MyOSLogHandler(label: $0) }
```

Default your handler's `logLevel` to `.trace` to match `OSLogSupabaseLogger`'s old always-forward
behavior — use Console.app's own filtering, or set `logger.logLevel` yourself, to narrow what's
emitted.

If this file also has `import OSLog` — which it will if you're implementing `MyOSLogHandler`
alongside your app's own OSLog-based logging — you'll hit a `'Logger' is ambiguous for type
lookup` compile error, because both `Logging.Logger` and `os.Logger` are now in scope unqualified
in that file. Fix it by fully qualifying whichever type you mean less often, e.g. `os.Logger` for
OSLog's own type:

```swift
import Logging
import OSLog

let appLogger = os.Logger(subsystem: "myapp", category: "app")
let supabaseLogger = Logging.Logger(label: "myapp") { MyOSLogHandler(label: $0) }
```

or keep the two imports in separate files so the ambiguity never arises.

**`SupabaseClient` + `RealtimeClientOptions.logger`.** If you construct a `RealtimeClientOptions`
with an explicit `logger:` and pass it to `SupabaseClientOptions(realtime:)`, `SupabaseClient` now
always overrides it with `SupabaseClientOptions.GlobalOptions.logger` — matching how the
Auth/PostgREST/Storage/Functions sub-clients already behaved, so Realtime is no longer the odd one
out. This is a silent behavior change, not a compile error: search your codebase for
`RealtimeClientOptions(` call sites that also set `logger:` and are passed through
`SupabaseClientOptions(realtime:)` — that logger is now ignored in favor of the global one.
Construct `RealtimeClientV2` directly (not through `SupabaseClient`) if you need a
Realtime-specific logger distinct from the rest of the client.

## `KeychainLocalStorage.retrieve` returns `nil` for a missing key instead of throwing

`AuthLocalStorage.retrieve(key:)` has always been documented as returning `nil` when the key is
absent, but `KeychainLocalStorage` didn't honor that: a missing item made the underlying
`SecItemCopyMatching` call return `errSecItemNotFound`, and that status was surfaced as a thrown
`KeychainError`, not as `nil`. `retrieve` now matches its own documentation and returns `nil` for
a missing item, throwing only when the Keychain read itself fails for another reason.

Two consequences of the old behavior made this worth fixing rather than just documenting: every
app launch with no stored session threw and typically got logged as an error, since "no session
yet" is the normal state on a fresh install; and call sites that wrapped the read in `try?` to
treat "no session" as `nil` also swallowed genuine Keychain failures (for example
`errSecInteractionNotAllowed` when the device is locked) into that same `nil`, turning a real error
into a silent, incorrect sign-out.

This fixes the Apple-platform implementation only. `WinCredLocalStorage`, the default on Windows,
still throws `WinCredLocalStorageError.windows` when `CredReadW` reports `ERROR_NOT_FOUND`, and its
`remove` is likewise not idempotent — so on Windows the protocol's documented contract is still not
honored. That implementation is being dropped in v3 in favor of requiring Windows callers to supply
their own `AuthLocalStorage`, tracked separately.

If you implement `AuthLocalStorage` yourself, follow the documented contract: return `nil` for an
absent key, and throw only on a genuine failure.

This is a behavior change, not a compile error — `retrieve`'s signature is unchanged. Search your
code for places that catch an error from `AuthLocalStorage.retrieve`/`KeychainLocalStorage.retrieve`
specifically to detect a missing session; that error no longer occurs, and you should instead
check the returned value for `nil`:

```swift
// Before
do {
  let data = try storage.retrieve(key: "supabase.session")
  // handle existing session
} catch {
  // this also ran for a plain "no session yet", not just real failures
}

// After
if let data = try storage.retrieve(key: "supabase.session") {
  // handle existing session
} else {
  // no session stored — the normal case on first launch
}
```

If you have a custom `AuthLocalStorage` implementation, update it to return `nil` when the key is
absent and reserve `throw` for genuine failures. `remove(key:)` was changed the same way: deleting
an already-absent key is no longer an error and is treated as a no-op.

## Opt-in macOS data-protection Keychain

`KeychainLocalStorage`'s two initializers gained a `useDataProtectionKeychain` parameter,
defaulting to `false`. This is additive — existing call sites keep compiling and keep their
current behavior — but it's documented here because it's the fix for a common source of
confusion: on macOS, the legacy file-based Keychain that `KeychainLocalStorage` targets by default
still shows the user a consent prompt tied to your app's designated requirement, regardless of the
service name — the ACL that triggers the prompt is governed by code-signing identity, not by
`kSecAttrService` (see [Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)).
Passing `useDataProtectionKeychain: true` moves storage to the data-protection Keychain, which
does not show that prompt.

```swift
let storage = KeychainLocalStorage(useDataProtectionKeychain: true)
```

One qualification for existing installs: items do not move between the two Keychain
implementations, so the first read after you enable the flag still probes the old file-based
location to migrate the session across. Reading an ACL-protected item there can show the prompt
one final time. Once the value has migrated, the file-based location is no longer read and the
prompt stops.

This has a real requirement, not just a flag flip: the data-protection Keychain only works in an
app signed with entitlements authorized by a provisioning profile. Without them, every Keychain
operation fails with `errSecMissingEntitlement` (`-34018`) instead of storing anything. Verify the
flag works with your app's actual signing configuration — a debug build run from Xcode with the
right entitlements is not the same guarantee as your release signing — before enabling it in
production. The parameter has no effect on platforms other than macOS.

## `WinCredLocalStorage` removed; no default `AuthLocalStorage` on Windows

`WinCredLocalStorage` and `WinCredLocalStorageError` are removed, and
`AuthClient.Configuration.defaultLocalStorage` is no longer defined on Windows. Windows callers now
need to supply their own `AuthLocalStorage` explicitly, the same as Linux and Android already
require.

`WinCredLocalStorage` was the default local storage on Windows, but it could not persist a
session: writes targeted a Windows Credential Manager entry named `service\key`, while reads and
deletes targeted `service\key)` — a stray trailing `)` — so nothing this code wrote could ever be
read back. It also stored the in-memory layout of the `Data` struct rather than the bytes it
pointed to, escaped several pointers past the closures that made them valid, and threw instead of
returning `nil` for a missing key. No Windows runner exists in this project's CI, and no test
referenced the type, so none of this was ever caught. If you were relying on the default, you were
already effectively running without session persistence on Windows.

This is a compile error, not a silent behavior change: any call site building
`AuthClient.Configuration` or `SupabaseClientOptions.AuthOptions` on Windows without passing
`storage:`/`localStorage:` explicitly now fails to compile, since the default no longer exists for
that platform.

```swift
// Before (Windows)
let client = SupabaseClient(supabaseURL: url, supabaseKey: key)

// After (Windows)
struct MyLocalStorage: AuthLocalStorage {
  func store(key: String, value: Data) throws { /* ... */ }
  func retrieve(key: String) throws -> Data? { /* ... */ }
  func remove(key: String) throws { /* ... */ }
}

let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(auth: .init(storage: MyLocalStorage()))
)
```

There's no reference implementation to swap in — implement `AuthLocalStorage` against whatever
storage mechanism suits your app.

## `AnyJSON` renamed to `JSONValue`

The `Helpers` type `AnyJSON` is now `JSONValue`. `AnyJSON` described a Postgres/JSON column value
long before the SDK had any other `Any`-prefixed types; `JSONValue` names what the type actually
holds and matches the naming used for the same concept in supabase-js. `JSONObject` and
`JSONArray` keep their names — only the enum itself is renamed.

```swift
// Before
let json: AnyJSON = ["id": 1, "name": "Bo"]
func decode(_ value: AnyJSON) throws -> User { try value.decode() }

// After
let json: JSONValue = ["id": 1, "name": "Bo"]
func decode(_ value: JSONValue) throws -> User { try value.decode() }
```

This is a compile error everywhere `AnyJSON` is spelled out as a type — search your codebase for
`AnyJSON` and replace it with `JSONValue`. Values and call sites that never name the type
explicitly (e.g. `let json: JSONObject = [...]`, or `try SomeType(from: value)`) are unaffected.

## `FactorStatus` is now a struct, not an enum

`FactorStatus` (the enrollment status on an MFA `Factor`) is a `RawRepresentable` struct instead
of an `enum`.

GoTrue can add new factor statuses over time; as an `enum`, decoding a `Factor` with a status this
SDK version didn't know about threw a `DecodingError` instead of surfacing the factor with its
unrecognized status intact.

```swift
// Before
switch factor.status {
case .verified: ...
case .unverified: ...
}

// After
switch factor.status {
case .verified: ...
case .unverified: ...
default: ...  // an unrecognized status the SDK doesn't have a case for
}
```

This is a compile error only if you have an exhaustive `switch` over `FactorStatus` — add a
`default:` case. Equality (`factor.status == .verified`) and construction from a literal
(`let status: FactorStatus = "verified"`) work unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = FactorStatus(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = FactorStatus(rawValue: someString)` directly. If your code used
`FactorStatus(rawValue:) != nil` to validate a string, that check still compiles but is now always
`true` — this is a silent behavior change, not a compile error, so search for that pattern and
remove or replace it.

String interpolation of a `FactorStatus` value also changes silently: `"\(FactorStatus.verified)"`-
style interpolation used to print the case name (`verified`); it now prints the struct's default
description (`FactorStatus(rawValue: "verified")`). If you log, build a URL, or send analytics
using direct interpolation of a `FactorStatus` value, use `.rawValue` explicitly to get the bare
string back.

## `MessagingChannel` is now a struct, not an enum

`MessagingChannel` (the OTP delivery channel — SMS or WhatsApp) is a `RawRepresentable` struct
instead of an `enum`. It's `Encodable` only — it's never decoded from a response, so it gained no
`Decodable` conformance.

It's part of the public API surface — if GoTrue starts accepting a new channel (e.g. Telegram),
constructing that value as an enum required an SDK upgrade even though nothing about sending it
needs one. Converting now closes that gap ahead of time.

```swift
// Before
switch channel {
case .sms: ...
case .whatsapp: ...
}

// After
switch channel {
case .sms: ...
case .whatsapp: ...
default: ...  // an unrecognized channel the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `MessagingChannel` — add a `default:`
case. Passing `.sms` / `.whatsapp` as an argument, and comparing with `==`, work unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = MessagingChannel(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = MessagingChannel(rawValue: someString)` directly. If your code used
`MessagingChannel(rawValue:) != nil` to validate a string, that check still compiles but is now
always `true` — this is a silent behavior change, not a compile error, so search for that pattern
and remove or replace it.

String interpolation of a `MessagingChannel` value also changes silently:
`"\(MessagingChannel.sms)"`-style interpolation used to print the case name (`sms`); it now prints
the struct's default description (`MessagingChannel(rawValue: "sms")`). If you log, build a URL, or
send analytics using direct interpolation of a `MessagingChannel` value, use `.rawValue` explicitly
to get the bare string back.

## `Provider` is now a struct, not an enum

`Provider` (the OAuth provider used by `signInWithOAuth`/`linkIdentity`) is a `RawRepresentable`
struct instead of an `enum`. It no longer conforms to `CaseIterable`, `Identifiable`, or `Codable`
(it never went through `JSONEncoder`/`JSONDecoder` to begin with — see "Several public types
narrowed from `Codable` to `Decodable` or `Encodable`" above).

New OAuth providers are added by GoTrue on an ongoing basis, and `Provider` is part of the public
API surface — as an `enum`, constructing a `Provider` value this SDK version didn't have a case
for required an SDK upgrade even though nothing about using it needs one. Converting now closes
that gap.

**Switch statements** — add a `default:` case:

```swift
// Before
switch provider {
case .apple: ...
case .github: ...
}

// After
switch provider {
case .apple: ...
case .github: ...
default: ...  // a provider the SDK doesn't have a case for
}
```

This is a compile error only if you have an exhaustive `switch` over `Provider` — add a `default:`
case.

**`Provider.allCases`** — no longer exists, with no built-in replacement. `Provider` accepts any
string, including ones the SDK has no static constant for, so an exhaustive list can't be part of
the type itself; maintain your own array of the providers your app actually offers:

```swift
// Before
Provider.allCases.forEach { ... }

// After
let myAppProviders: [Provider] = [.apple, .google, .github]  // whatever your app offers
myAppProviders.forEach { ... }
```

This is a compile error (`allCases` no longer exists).

**`Identifiable`** — no longer conforms. If you used `Provider` directly in a SwiftUI `ForEach` or
`List` relying on its `Identifiable` conformance, supply an explicit `id:` — `Provider` is still
`Hashable`, so `\.self` works:

```swift
// Before
ForEach(providers) { provider in ... }

// After
ForEach(providers, id: \.self) { provider in ... }
```

This is a compile error (`ForEach`/`List` without an explicit `id:` require `Identifiable`).

**Custom providers** — construct one from a string literal or `rawValue` the same way you would
compare against a known one:

```swift
let provider: Provider = "custom_provider"
if provider == .apple { ... }
if provider.rawValue == "apple" { ... }
```

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = Provider(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with `let x = Provider(rawValue:
someString)` directly. If your code used `Provider(rawValue:) != nil` to validate a string, that
check still compiles but is now always `true` — this is a silent behavior change, not a compile
error, so search for that pattern and remove or replace it.

String interpolation of a `Provider` value also changes silently: `"\(Provider.apple)"`-style
interpolation used to print the case name (`apple`); it now prints the struct's default description
(`Provider(rawValue: "apple")`). If you log, build a URL, or send analytics using direct
interpolation of a `Provider` value, use `.rawValue` explicitly to get the bare string back.

## `OpenIDConnectCredentials.Provider` is now a struct, not an enum

`OpenIDConnectCredentials.Provider` (the OIDC provider passed to `signInWithIdToken`) is a
`RawRepresentable` struct instead of an `enum`.

It's sent to the backend, not decoded from it — it's `Encodable`-only, not full `Codable` — but
it's part of the public API surface, and the set of OIDC-capable providers can grow. As an `enum`,
using a provider this SDK version didn't have a case for meant waiting on an SDK upgrade even
though GoTrue might already support it.

```swift
// Before
switch credentials.provider {
case .apple: ...
case .google: ...
}

// After
switch credentials.provider {
case .apple: ...
case .google: ...
default: ...  // a provider the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over this type — add a `default:` case.
Constructing and comparing known providers (`OpenIDConnectCredentials(provider: .apple, ...)`,
`provider == .google`) work unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = OpenIDConnectCredentials.Provider(rawValue: someString) { ... }` no longer compiles
("Initializer for conditional binding must have Optional type") — replace it with
`let x = OpenIDConnectCredentials.Provider(rawValue: someString)` directly. If your code used
`OpenIDConnectCredentials.Provider(rawValue:) != nil` to validate a string, that check still
compiles but is now always `true` — this is a silent behavior change, not a compile error, so
search for that pattern and remove or replace it.

String interpolation of an `OpenIDConnectCredentials.Provider` value also changes silently:
`"\(OpenIDConnectCredentials.Provider.apple)"`-style interpolation used to print the case name
(`apple`); it now prints the struct's default description
(`OpenIDConnectCredentials.Provider(rawValue: "apple")`). If you log, build a URL, or send
analytics using direct interpolation of an `OpenIDConnectCredentials.Provider` value, use
`.rawValue` explicitly to get the bare string back.

## `MobileOTPType` is now a struct, not an enum

`MobileOTPType` (the OTP kind passed to `verifyOTP` for phone-based flows) is a `RawRepresentable`
struct instead of an `enum`.

It's sent to the backend, not decoded from it, but it's part of the public API surface — as an
`enum`, using an OTP type GoTrue added after this SDK version shipped required an SDK upgrade
even though constructing the value doesn't need one.

```swift
// Before
switch type {
case .sms: ...
case .phoneChange: ...
}

// After
switch type {
case .sms: ...
case .phoneChange: ...
default: ...  // an OTP type the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `MobileOTPType` — add a `default:` case.
Passing `.sms` / `.phoneChange` as an argument works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = MobileOTPType(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = MobileOTPType(rawValue: someString)` directly. If your code used
`MobileOTPType(rawValue:) != nil` to validate a string, that check still compiles but is now always
`true` — this is a silent behavior change, not a compile error, so search for that pattern and
remove or replace it.

String interpolation of a `MobileOTPType` value also changes silently: `"\(MobileOTPType.sms)"`-
style interpolation used to print the case name (`sms`); it now prints the struct's default
description (`MobileOTPType(rawValue: "sms")`). If you log, build a URL, or send analytics using
direct interpolation of a `MobileOTPType` value, use `.rawValue` explicitly to get the bare string
back.

## `EmailOTPType` is now a struct, not an enum

`EmailOTPType` (the OTP kind passed to `verifyOTP` for email-based flows) is a `RawRepresentable`
struct instead of an `enum`. It no longer conforms to `CaseIterable`.

It's sent to the backend, not decoded from it, but it's part of the public API surface — as an
`enum`, using an OTP type GoTrue added after this SDK version shipped required an SDK upgrade
even though constructing the value doesn't need one.

```swift
// Before
switch type {
case .signup: ...
case .recovery: ...
// ...
}

// After
switch type {
case .signup: ...
case .recovery: ...
// ...
default: ...  // an OTP type the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `EmailOTPType` — add a `default:` case.
`EmailOTPType.allCases` no longer exists, with no built-in replacement — maintain your own array if
you were relying on it.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = EmailOTPType(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = EmailOTPType(rawValue: someString)` directly. If your code used
`EmailOTPType(rawValue:) != nil` to validate a string, that check still compiles but is now always
`true` — this is a silent behavior change, not a compile error, so search for that pattern and
remove or replace it.

String interpolation of an `EmailOTPType` value also changes silently: `"\(EmailOTPType.signup)"`-
style interpolation used to print the case name (`signup`); it now prints the struct's default
description (`EmailOTPType(rawValue: "signup")`). If you log, build a URL, or send analytics using
direct interpolation of an `EmailOTPType` value, use `.rawValue` explicitly to get the bare string
back.

## `ResendEmailType` is now a struct, not an enum

`ResendEmailType` (the resend kind passed to `resend`) is a `RawRepresentable` struct instead of
an `enum`.

It's sent to the backend, not decoded from it, but it's part of the public API surface — as an
`enum`, using a resend type GoTrue added after this SDK version shipped required an SDK upgrade
even though constructing the value doesn't need one.

```swift
// Before
switch type {
case .signup: ...
case .emailChange: ...
}

// After
switch type {
case .signup: ...
case .emailChange: ...
default: ...  // a resend type the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `ResendEmailType` — add a `default:`
case. Passing `.signup` / `.emailChange` as an argument works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = ResendEmailType(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = ResendEmailType(rawValue: someString)` directly. If your code used
`ResendEmailType(rawValue:) != nil` to validate a string, that check still compiles but is now
always `true` — this is a silent behavior change, not a compile error, so search for that pattern
and remove or replace it.

String interpolation of a `ResendEmailType` value also changes silently:
`"\(ResendEmailType.signup)"`-style interpolation used to print the case name (`signup`); it now
prints the struct's default description (`ResendEmailType(rawValue: "signup")`). If you log, build
a URL, or send analytics using direct interpolation of a `ResendEmailType` value, use `.rawValue`
explicitly to get the bare string back.

## `ResendMobileType` is now a struct, not an enum

`ResendMobileType` (the resend kind passed to `resend` for phone-based flows) is a
`RawRepresentable` struct instead of an `enum`.

It's sent to the backend, not decoded from it, but it's part of the public API surface — as an
`enum`, using a resend type GoTrue added after this SDK version shipped required an SDK upgrade
even though constructing the value doesn't need one.

```swift
// Before
switch type {
case .sms: ...
case .phoneChange: ...
}

// After
switch type {
case .sms: ...
case .phoneChange: ...
default: ...  // a resend type the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `ResendMobileType` — add a `default:`
case. Passing `.sms` / `.phoneChange` as an argument works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = ResendMobileType(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = ResendMobileType(rawValue: someString)` directly. If your code used
`ResendMobileType(rawValue:) != nil` to validate a string, that check still compiles but is now
always `true` — this is a silent behavior change, not a compile error, so search for that pattern
and remove or replace it.

String interpolation of a `ResendMobileType` value also changes silently:
`"\(ResendMobileType.sms)"`-style interpolation used to print the case name (`sms`); it now prints
the struct's default description (`ResendMobileType(rawValue: "sms")`). If you log, build a URL, or
send analytics using direct interpolation of a `ResendMobileType` value, use `.rawValue` explicitly
to get the bare string back.

## `SignOutScope` is now a struct, not an enum

`SignOutScope` (passed to `signOut(scope:)`) is a `RawRepresentable` struct instead of an `enum`.

It's sent to the backend as a query parameter, not decoded from it, but it's part of the public
API surface — as an `enum`, using a scope GoTrue added after this SDK version shipped required an
SDK upgrade even though constructing the value doesn't need one.

```swift
// Before
switch scope {
case .global: ...
case .local: ...
case .others: ...
}

// After
switch scope {
case .global: ...
case .local: ...
case .others: ...
default: ...  // a scope the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `SignOutScope` — add a `default:` case.
Passing `.global` / `.local` / `.others` as an argument works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = SignOutScope(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = SignOutScope(rawValue: someString)` directly. If your code used
`SignOutScope(rawValue:) != nil` to validate a string, that check still compiles but is now always
`true` — this is a silent behavior change, not a compile error, so search for that pattern and
remove or replace it.

String interpolation of a `SignOutScope` value also changes silently: `"\(SignOutScope.global)"`-
style interpolation used to print the case name (`global`); it now prints the struct's default
description (`SignOutScope(rawValue: "global")`). If you log, build a URL, or send analytics using
direct interpolation of a `SignOutScope` value, use `.rawValue` explicitly to get the bare string
back.

## `PostgrestFilterBuilder.Operator` is now a struct, not an enum

`PostgrestFilterBuilder.Operator` (passed to `not(_:operator:value:)`) is a `RawRepresentable`
struct instead of an `enum`. It no longer conforms to `CaseIterable`.

It's sent to PostgREST as part of a filter query string, not decoded from a response, but it's
part of the public API surface — as an `enum`, using an operator PostgREST added after this SDK
version shipped required an SDK upgrade even though constructing the value doesn't need one.

```swift
// Before
switch op {
case .eq: ...
case .neq: ...
// ...
}

// After
switch op {
case .eq: ...
case .neq: ...
// ...
default: ...  // an operator the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `Operator` — add a `default:` case.
`Operator.allCases` no longer exists, with no built-in replacement — maintain your own array if you
were relying on it. Passing a known operator (`.eq`, `.gt`, ...) works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = PostgrestFilterBuilder.Operator(rawValue: someString) { ... }` no longer compiles
("Initializer for conditional binding must have Optional type") — replace it with
`let x = PostgrestFilterBuilder.Operator(rawValue: someString)` directly. If your code used
`PostgrestFilterBuilder.Operator(rawValue:) != nil` to validate a string, that check still compiles
but is now always `true` — this is a silent behavior change, not a compile error, so search for
that pattern and remove or replace it.

String interpolation of a `PostgrestFilterBuilder.Operator` value also changes silently:
`"\(PostgrestFilterBuilder.Operator.eq)"`-style interpolation used to print the case name (`eq`);
it now prints the struct's default description (`PostgrestFilterBuilder.Operator(rawValue: "eq")`).
If you log, build a URL, or send analytics using direct interpolation of a
`PostgrestFilterBuilder.Operator` value, use `.rawValue` explicitly to get the bare string back.

The operator type is now declared at the top level as `PostgrestOperator`, with
`PostgrestFilterBuilder.Operator` kept as a type alias for it — so every spelling above keeps
working, and diagnostics that mention `PostgrestOperator` are referring to the same type. Nothing to
change; this is additive.

## `CountOption` is now a struct, not an enum

`CountOption` (passed to query methods like `select(_:head:count:)`) is a `RawRepresentable`
struct instead of an `enum`.

It's sent to PostgREST as part of a `Prefer` header, not decoded from a response, but it's part of
the public API surface — as an `enum`, using a count algorithm PostgREST added after this SDK
version shipped required an SDK upgrade even though constructing the value doesn't need one.

```swift
// Before
switch count {
case .exact: ...
case .planned: ...
case .estimated: ...
}

// After
switch count {
case .exact: ...
case .planned: ...
case .estimated: ...
default: ...  // a count algorithm the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `CountOption` — add a `default:` case.
Passing `.exact` / `.planned` / `.estimated` as an argument works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = CountOption(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = CountOption(rawValue: someString)` directly. If your code used
`CountOption(rawValue:) != nil` to validate a string, that check still compiles but is now always
`true` — this is a silent behavior change, not a compile error, so search for that pattern and
remove or replace it.

String interpolation of a `CountOption` value also changes silently: `"\(CountOption.exact)"`-style
interpolation used to print the case name (`exact`); it now prints the struct's default description
(`CountOption(rawValue: "exact")`). If you log, build a URL, or send analytics using direct
interpolation of a `CountOption` value, use `.rawValue` explicitly to get the bare string back.

## `PostgrestReturningOptions` is now a struct, not an enum

`PostgrestReturningOptions` (passed to `insert`/`update`/`upsert`/`delete`) is a `RawRepresentable`
struct instead of an `enum`.

It's sent to PostgREST as part of a `Prefer` header, not decoded from a response, but it's part of
the public API surface — as an `enum`, using a returning mode PostgREST added after this SDK
version shipped required an SDK upgrade even though constructing the value doesn't need one.

```swift
// Before
switch returning {
case .minimal: ...
case .representation: ...
}

// After
switch returning {
case .minimal: ...
case .representation: ...
default: ...  // a returning mode the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `PostgrestReturningOptions` — add a
`default:` case. Passing `.minimal` / `.representation` as an argument works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = PostgrestReturningOptions(rawValue: someString) { ... }` no longer compiles
("Initializer for conditional binding must have Optional type") — replace it with
`let x = PostgrestReturningOptions(rawValue: someString)` directly. If your code used
`PostgrestReturningOptions(rawValue:) != nil` to validate a string, that check still compiles but
is now always `true` — this is a silent behavior change, not a compile error, so search for that
pattern and remove or replace it.

String interpolation of a `PostgrestReturningOptions` value also changes silently:
`"\(PostgrestReturningOptions.minimal)"`-style interpolation used to print the case name
(`minimal`); it now prints the struct's default description
(`PostgrestReturningOptions(rawValue: "minimal")`). If you log, build a URL, or send analytics
using direct interpolation of a `PostgrestReturningOptions` value, use `.rawValue` explicitly to
get the bare string back.

## `TextSearchType` is now a struct, not an enum

`TextSearchType` (passed to `textSearch(_:query:config:type:)`) is a `RawRepresentable` struct
instead of an `enum`.

It's sent to PostgREST as part of a filter query string, not decoded from a response, but it's
part of the public API surface — as an `enum`, using a search conversion strategy PostgreSQL added
after this SDK version shipped required an SDK upgrade even though constructing the value doesn't
need one.

```swift
// Before
switch type {
case .plain: ...
case .phrase: ...
case .websearch: ...
}

// After
switch type {
case .plain: ...
case .phrase: ...
case .websearch: ...
default: ...  // a search type the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `TextSearchType` — add a `default:`
case. Passing `.plain` / `.phrase` / `.websearch` as an argument works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = TextSearchType(rawValue: someString) { ... }` no longer compiles ("Initializer for
conditional binding must have Optional type") — replace it with
`let x = TextSearchType(rawValue: someString)` directly. If your code used
`TextSearchType(rawValue:) != nil` to validate a string, that check still compiles but is now
always `true` — this is a silent behavior change, not a compile error, so search for that pattern
and remove or replace it.

String interpolation of a `TextSearchType` value also changes silently: `"\(TextSearchType.plain)"`
-style interpolation used to print the case name (`plain`); it now prints the struct's default
description (`TextSearchType(rawValue: "pl")`) — note this shows the underlying PostgREST raw
value (`pl`), not the case name, since `TextSearchType`'s raw values don't match its case names. If
you log, build a URL, or send analytics using direct interpolation of a `TextSearchType` value, use
`.rawValue` explicitly to get the bare string back.

## `FunctionInvokeOptions.Method` is now a struct, not an enum

`FunctionInvokeOptions.Method` (the HTTP method passed to `invoke`) is a `RawRepresentable` struct
instead of an `enum`, matching `HTTPTypes.HTTPRequest.Method` from `swift-http-types`, which uses
the same pattern.

```swift
// Before
switch method {
case .get: ...
case .post: ...
// ...
}

// After
switch method {
case .get: ...
case .post: ...
// ...
default: ...  // a method the SDK doesn't have a case for
}
```

Compile error only if you have an exhaustive `switch` over `Method` — add a `default:` case.
Passing `.get` / `.post` / `.put` / `.patch` / `.delete` as an argument works unchanged.

`init(rawValue:)` is no longer failable — it now always succeeds, even for an unrecognized value.
`if let x = FunctionInvokeOptions.Method(rawValue: someString) { ... }` no longer compiles
("Initializer for conditional binding must have Optional type") — replace it with
`let x = FunctionInvokeOptions.Method(rawValue: someString)` directly. If your code used
`FunctionInvokeOptions.Method(rawValue:) != nil` to validate a string, that check still compiles
but is now always `true` — this is a silent behavior change, not a compile error, so search for
that pattern and remove or replace it.

String interpolation of a `FunctionInvokeOptions.Method` value also changes silently:
`"\(FunctionInvokeOptions.Method.get)"`-style interpolation used to print the case name (`get`); it
now prints the struct's default description (`FunctionInvokeOptions.Method(rawValue: "GET")`). If
you log, build a URL, or send analytics using direct interpolation of a
`FunctionInvokeOptions.Method` value, use `.rawValue` explicitly to get the bare string back.

Constructing a `Method` from an arbitrary string is not validated at construction time — invalid
HTTP method tokens are caught later, in `httpMethod(_:)`, which returns `nil` for a raw value that
isn't a legal HTTP token (per RFC 9110). `FunctionsClient` falls back to `.post` when `httpMethod`
returns `nil`, so an invalid custom `Method` silently becomes a POST request rather than throwing.

## `FunctionsClient.setAuth(token:)` removed; pass an `accessToken` closure instead

`FunctionsClient.setAuth(token:)` is removed. Every initializer now takes an optional
`accessToken: (@Sendable () async throws -> String?)?` closure instead. `FunctionsClient` calls it
fresh before each request and sends the result as `Authorization: Bearer <token>`.

`setAuth` mutated a lock-protected header stored on the client — its only mutable state; every
other property was already immutable configuration set at `init`. That mutation had no effect when
`FunctionsClient` came from `SupabaseClient.functions`: that client's `fetch` handler already
overwrites `Authorization` on every request with the live session token, so `SupabaseClient`'s
internal `functions.setAuth(...)` call (made on every auth state change) never changed a request
that actually went out on the wire. Moving to a pull-based closure removes the lock and that dead
call, and gives a standalone `FunctionsClient` (built directly, not through `SupabaseClient`) a way
to keep its token current without a separate setter.

```swift
// Before
let client = FunctionsClient(url: url, headers: ["apikey": apiKey])
client.setAuth(token: session.accessToken)

// After
let client = FunctionsClient(
  url: url,
  headers: ["apikey": apiKey],
  accessToken: { session.accessToken }
)
```

This is a compile error, not a silent behavior change: any call site using `setAuth` fails to
build.

If you only use `FunctionsClient` through `SupabaseClient.functions`, there's nothing to change —
`SupabaseClient` removed its internal `setAuth` call along with the method, but it changed no
header on the wire, since `SupabaseClient`'s request adapter already supplied the live bearer
token.

## `FunctionsClient` is now a `struct` instead of a `class`

`FunctionsClient` no longer holds any mutable state — the `setAuth` removal above took away its
only `let`-backed lock — so every stored property is now an immutable `let`, and the type itself is
a `struct`.

Calling methods (`invoke`, `_invokeWithStreamedResponse`, and friends) compiles unchanged; this
only breaks code that depended on `FunctionsClient` being a reference type: a `weak var` holding
one, an `AnyObject` constraint, or an identity check with `===`. None of those compile against a
struct.

```swift
// Before
weak var client: FunctionsClient?

// After
// Structs have no identity to hold weakly — keep a strong reference, or drop the field if it only
// existed to avoid a retain cycle: `FunctionsClient` has never captured `self` from its owner.
var client: FunctionsClient?
```

This is a compile error, not a silent behavior change. Search your codebase for `weak`, `unowned`,
`AnyObject`, or `===` next to a `FunctionsClient` variable to find affected call sites.

## `PostgrestClient.setAuth(_:)` is removed; pass an `accessToken` closure instead

`PostgrestClient.setAuth(_:)` is removed. Every initializer now takes an optional
`accessToken: (@Sendable () async throws -> String?)?` closure instead. `PostgrestClient` calls it
fresh before each request and sends the result as `Authorization: Bearer <token>`.

`setAuth` mutated a lock-protected `Authorization` header stored on the client, the same pattern
`FunctionsClient.setAuth(token:)` went through earlier (see above). Moving to a pull-based closure
removes that lock and lets a token that expires and refreshes — e.g. one paired with Supabase
Auth — stay current without a separate setter call on every refresh.

```swift
// Before
let client = PostgrestClient(url: url)
client.setAuth(token)

// After — static token
let client = PostgrestClient(url: url, accessToken: { token })

// After — refreshable token, e.g. paired with Supabase Auth
let client = PostgrestClient(url: url, accessToken: { try await auth.session.accessToken })
```

This is a compile error, not a silent behavior change: any call site using `setAuth` fails to
build.

An `Authorization` header already set via `Configuration.headers`, or via an explicit
`.setHeader("Authorization", ...)` call on a builder, always takes precedence over the
`accessToken` closure's result.

## `PostgrestClient` and its builders are now structs, not classes

`PostgrestClient`, `PostgrestQueryBuilder`, `PostgrestFilterBuilder`, and
`PostgrestTransformBuilder` are structs instead of classes. The `setAuth` removal above took away
`PostgrestClient`'s only mutable, lock-protected state, so every one of its stored properties is
now an immutable `let`. The builder types held their own per-request state (headers, retry flag,
pending-error tracking) the same lock-protected way; removing that lock made them structs too, but
they still have `var` stored properties — each chained call (`select`, `eq`, `setHeader`, ...)
copies `self`, mutates the copy, and returns it, rather than mutating shared state in place.

Under the hood, `PostgrestQueryBuilder`, `PostgrestFilterBuilder`, and `PostgrestTransformBuilder`
are now `typealias`es of a single generic `PostgrestRequestBuilder<Phase>` type, where `Phase` is a
compile-time-only marker that determines which methods are available. `PostgrestBuilder` has no
replacement name at all — it was removed outright (see the next two sections for what that means for
your code).

Calling methods (`from`, `select`, `eq`, `execute`, and friends) compiles unchanged; this only
breaks code that depended on these types being reference types: a `weak var` holding one, an
`AnyObject` constraint, or an identity check with `===`. None of those compile against a struct.
Subclassing any of the builder types is also no longer possible, since none of them are classes
anymore — this was previously possible because none of the builder classes were `final`.

```swift
// Before
weak var client: PostgrestClient?

// After
// Structs have no identity to hold weakly — keep a strong reference, or drop the field if it only
// existed to avoid a retain cycle.
var client: PostgrestClient?
```

This is a compile error, not a silent behavior change. Search your codebase for `weak`, `unowned`,
`AnyObject`, `===`, or a subclass declaration next to `PostgrestClient`, `PostgrestBuilder`,
`PostgrestQueryBuilder`, `PostgrestFilterBuilder`, or `PostgrestTransformBuilder` to find affected
call sites.

## `PostgrestBuilder` is no longer a nameable, non-generic type

Code that spells out `PostgrestBuilder` as a type — a stored property, a function parameter or
return type — no longer compiles. The type was removed outright: there is no `PostgrestBuilder`
type alias, and no non-generic supertype shared by the phase-specific builders. Use the new
`any PostgrestExecutableBuilder` protocol for "any executable PostgREST builder regardless of
phase," or name one of the concrete phase-specific type aliases (`PostgrestFilterBuilder`,
`PostgrestTransformBuilder`) directly:

```swift
// Before
func makeUsersQuery(_ client: PostgrestClient) -> PostgrestBuilder {
  client.from("users").select()
}

// After
func makeUsersQuery(_ client: PostgrestClient) -> any PostgrestExecutableBuilder {
  client.from("users").select()
}

// `PostgrestExecutableBuilder.execute(options:)` is a protocol requirement, so it can't carry
// `@discardableResult` — bind or use the result to avoid an "unused result" warning.
_ = try await makeUsersQuery(client).execute(options: FetchOptions())
```

`any PostgrestExecutableBuilder` only exposes `execute(options:)` — it doesn't carry
`setHeader`/`retry`, since those are declared directly on `PostgrestRequestBuilder<Phase>` and
constrained to phases conforming to `PostgrestExecutablePhase`, not on the protocol itself. Code
that needs to call `setHeader`/`retry` generically must keep the concrete phase type instead of
erasing to `any PostgrestExecutableBuilder`.

This is a compile error, not a silent behavior change.

## `PostgrestQueryBuilder` no longer supports `execute()`/`setHeader(...)`/`retry(...)` before an operation

`client.from("table").execute()` — calling `execute()` (or `setHeader`/`retry`) without first
calling `select`/`insert`/`update`/`upsert`/`delete` — no longer compiles. This closes a
previously-compiling but apparently-unused capability; the fix is to call one of those operations
first:

```swift
// Before (compiled, but sent an implicit "select *")
try await client.from("todos").execute()

// After
try await client.from("todos").select().execute()
```

This also removes `setHeader(...)` from the builder `from(_:)` returns, before an operation is
chosen. If you relied on setting a header there — the operation methods (`select`/`insert`/
`update`/`upsert`/`delete`) merge their own `Prefer` value with whatever the request already
carries — set it via `PostgrestClient.Configuration.headers` instead. A client-level header
applies to every request from that client, and the operation methods still merge with it the same
way:

```swift
// Before — a Prefer header set on the query-phase builder, merged by select(count:) into
// "params=single-object,count=exact"
let client = PostgrestClient(url: url)
let todos: [Todo] = try await client
  .from("todos")
  .setHeader(name: "Prefer", value: "params=single-object")
  .select(count: .exact)
  .execute()
  .value

// After — set the Prefer header at the client level; select(count:) still merges it
let client = PostgrestClient(
  url: url,
  headers: ["Prefer": "params=single-object"]
)
let todos: [Todo] = try await client
  .from("todos")
  .select(count: .exact)
  .execute()
  .value
```

This is a compile error, not a silent behavior change: any call site chaining `execute`/
`setHeader`/`retry` directly onto `from(_:)` fails to build.

## `setHeader(name:value:)` and `retry(enabled:)` no longer carry `@discardableResult`

> Warning: This is the one PostgREST item on this page that is **not** a compile error. It is a
> warning you can miss.

When the builders were classes, `setHeader(name:value:)` and `retry(enabled:)` mutated the receiver
in place and returned `self` only for chaining convenience, so both were marked
`@discardableResult`. Now that the builders are structs, both methods return a **new** value and
leave the receiver untouched. `@discardableResult` was therefore removed: dropping the return value
would silently drop the header or the retry setting.

```swift
// Before — mutated `q` in place, chained call not required
let q = client.from("todos").select()
q.setHeader(name: "X-Foo", value: "1")
try await q.execute()

// After — setHeader/retry return a NEW value; you must use the result
var q = client.from("todos").select()
q = q.setHeader(name: "X-Foo", value: "1")
try await q.execute()
```

The "before" spelling still compiles. It produces a `result of call to 'setHeader(name:value:)' is
unused` warning instead of an error, and at runtime the header (or the `retry(enabled:)` setting) is
simply not applied. Search your codebase for `setHeader(` and `retry(enabled:` on a PostgREST
builder and make sure every call site consumes the returned value — either by chaining directly onto
it or by reassigning, as above.
## `StorageApi`, `SupabaseStorageClient`, and `StorageFileApi` are now `struct`s instead of `class`es; `StorageBucketApi` is removed

These types no longer hold any mutable state — the only mutable state they had was the header
dictionary `setHeader(_:forKey:)` wrote to, which is now handled by returning a new value instead
(see below) — so every stored property is now an immutable `let`, and the types themselves are now
`struct`s.

**Why**: beyond removing the lock, this is a real bug fix. `SupabaseStorageClient` used to store
its mutable header dictionary separately from its immutable `configuration`, and `from(_:)` built
each `StorageFileApi` from `configuration` alone — never from the live header state:

```swift
// Before, inside SupabaseStorageClient.from(_:):
public func from(_ id: String) -> StorageFileApi {
  StorageFileApi(bucketId: id, configuration: configuration)  // not the mutated headers
}
```

So `storage.setHeader("v", forKey: "X-Foo")` followed by `storage.from("bucket").list()` silently
dropped `X-Foo` — the new `StorageFileApi` never saw it. Meanwhile the same header *did* reach
`storage.vectors` calls, since `vectors` passed `self` (the live instance, headers and all) through
instead of rebuilding from `configuration`. This composition-based rewrite passes the whole `api`
value — which now carries the header state, since there's no separate mutable copy to drop —
through both `from(_:)` and `vectors`, so `setHeader` propagates consistently to both call paths.

`StorageBucketApi` is removed entirely. Nothing in this codebase ever constructed it directly; it
existed only so `SupabaseStorageClient` could inherit its bucket-management methods
(`listBuckets()`, `getBucket(_:)`, `createBucket(_:options:)`, `updateBucket(_:options:)`,
`emptyBucket(_:)`, `deleteBucket(_:)`). Those methods are now declared directly on
`SupabaseStorageClient` — call sites that only ever called them through `SupabaseStorageClient`
(e.g. `client.storage.listBuckets()`) compile unchanged. If your code constructed
`StorageBucketApi` directly — it was a public class with an inherited public initializer, so this
was possible even though nothing here did it — switch to constructing/using
`SupabaseStorageClient` instead; its methods are a superset, since the bucket methods moved there.

Calling methods (`from(_:)`, `upload`, `download`, `list`, and friends) compiles unchanged; this
only breaks code that depended on these types being reference types: a `weak var` holding one, an
`AnyObject` constraint, or an identity check with `===`. None of those compile against a struct.

```swift
// Before
weak var storage: SupabaseStorageClient?

// After
// Structs have no identity to hold weakly — keep a strong reference, or drop the field if it only
// existed to avoid a retain cycle.
var storage: SupabaseStorageClient?
```

This is a compile error, not a silent behavior change. Search your codebase for `weak`, `unowned`,
`AnyObject`, or `===` next to a `StorageApi`, `SupabaseStorageClient`, or `StorageFileApi` variable
to find affected call sites.

`SupabaseClient.storage` also stopped memoizing its result as a side effect of this rewrite: it
used to cache the `SupabaseStorageClient` it built and return that same instance on every access,
so a header set via `client.storage.setHeader(...)` (before `setHeader` even required using its
result, back when it mutated in place) stuck around across later `client.storage` accesses. Now
every `client.storage` access builds a fresh value, so nothing is around to remember a header
across accesses even if you do capture and reuse `setHeader`'s result:

```swift
// This does not persist the header on `client.storage` — the next access builds a new,
// unmodified instance from `client`'s own configuration.
_ = client.storage.setHeader("v", forKey: "X-Foo")
try await client.storage.from("bucket").list() // X-Foo is not sent

// Hold the returned value instead, and use it directly rather than going through
// `client.storage` again.
let storage = client.storage.setHeader("v", forKey: "X-Foo")
try await storage.from("bucket").list() // X-Foo is sent
```

## `setHeader(_:forKey:)` on `SupabaseStorageClient`/`StorageFileApi` no longer mutates in place

`setHeader(_:forKey:)` used to mutate a lock-protected header dictionary on the instance and return
`self` for chaining, marked `@discardableResult`. Now that these are immutable value types,
`setHeader` instead builds and returns a **new** value with the header merged in, and
`@discardableResult` is removed.

This is a silent behavior change, not a compile error, if you call `setHeader` and discard the
result — removing `@discardableResult` turns that into an "unused result" compiler warning rather
than a build failure, so it's easy to miss if warnings aren't treated as errors:

```swift
// Before: mutated the instance in place; the extra header applied to every later request.
storage.from("avatars").setHeader("x-custom-header", forKey: "X-Custom-Header")
try await storage.from("avatars").upload(...) // included the header

// After: returns a new value; the statement above is now a no-op, and the header is
// lost by the next line unless you capture and reuse the returned value.
let avatars = storage.from("avatars").setHeader("x-custom-header", forKey: "X-Custom-Header")
try await avatars.upload(...) // includes the header

// Or chain directly:
try await storage.from("avatars")
  .setHeader("x-custom-header", forKey: "X-Custom-Header")
  .upload(...)
```

Search your codebase for `.setHeader(` on a `SupabaseStorageClient`/`StorageFileApi` value to find
affected call sites, and check that each one uses the returned value rather than discarding it.

## `StorageApi` is now internal

`StorageApi` is removed from the public API. It was the shared implementation type
`SupabaseStorageClient`, `StorageFileApi`, and the Vectors trio each held internally and delegated
to — nothing in the public API ever accepted or returned one, so a directly-constructed
`StorageApi` value had no productive use: its `execute(_:)` method was already internal, and none
of the public client types exposed a way to build one from a standalone `StorageApi`. If your code
constructed `StorageApi(configuration:)` directly, construct a `SupabaseStorageClient(configuration:)`
instead — its public surface (`configuration`, `setHeader(_:forKey:)`, `from(_:)`) is a superset of
what `StorageApi` exposed.

## `PostgrestClient.Configuration.encoder`/`.decoder` are now `let`, not `var`

`PostgrestClient.Configuration.encoder` and `.decoder` are immutable, matching the `var` → `let`
direction the rest of `Configuration` already took when `PostgrestClient` became a stateless value
type. They were the last two settable properties left over from before that change — nothing in
the SDK ever mutated them after `init`, and the new per-call overrides below (on `insert`/`update`/
`upsert`/`execute`) cover the case that mutating them after construction was actually used for.

```swift
// Before
var configuration = PostgrestClient.Configuration(url: url)
configuration.decoder = myDecoder

// After — set it at construction time, or pass a per-call override (see below)
let configuration = PostgrestClient.Configuration(url: url, decoder: myDecoder)
```

This is a compile error, not a silent behavior change: any assignment to `.encoder`/`.decoder` on a
`PostgrestClient.Configuration` value no longer builds.

## PostgREST gains per-call `encoder`/`decoder` overrides; `PostgrestError` decoding no longer uses your decoder

`insert`, `update`, and `upsert` now accept a trailing `encoder: JSONEncoder? = nil`, and
`execute<T: Decodable>(options:)` now accepts a trailing `decoder: JSONDecoder? = nil` — each
overrides `PostgrestClient.Configuration.encoder`/`.decoder` for that one call. Calling these
methods without the new argument compiles unchanged.

```swift
// Encode this one insert with a different key strategy than the client default
try await client.from("todos")
  .insert(todo, encoder: mySnakeCaseEncoder)
  .execute()

// Decode this one response with a different date strategy than the client default
let todos: [Todo] = try await client.from("todos")
  .select()
  .execute(decoder: myCustomDecoder)
  .value
```

Separately, decoding a `PostgrestError` from an error response no longer uses
`Configuration.decoder` or either of these new per-call overrides — it always uses a fixed,
non-configurable internal decoder. Previously, a decoder with a non-default `keyDecodingStrategy`
or `dateDecodingStrategy` that didn't match `PostgrestError`'s plain `details`/`hint`/`code`/
`message` shape could cause a real PostgREST error response to fail decoding, and was reported as a
generic `HTTPError` instead of a `PostgrestError`. Now, a recognized PostgREST error body throws
`PostgrestError` with kind `.server` and the decoded `PostgrestError.ServerError` in `serverError`.
An unrecognized body throws the same kind `.server` with `serverError == nil` and the raw bytes
in `response?.body`. This is a silent behavior change, not a compile error: if you
`catch`-typed on `PostgrestError` while also customizing `Configuration.decoder`'s key or date
strategy, error responses that previously fell through as `HTTPError` are now caught as
`PostgrestError` instead.

## `PostgrestExecutableBuilder.execute<T: Decodable>(options:)` now requires a `decoder:` argument

The generic `execute` requirement on the `any PostgrestExecutableBuilder` protocol gained the same
`decoder: JSONDecoder?` parameter as the concrete `execute<T: Decodable>(options:decoder:)` above.
Protocol requirements can't carry a default argument, so calling it through the type-erased
`any PostgrestExecutableBuilder` — rather than through a concrete builder type, where the parameter
still defaults to `nil` — now requires passing `decoder:` explicitly:

```swift
// Before
let builder: any PostgrestExecutableBuilder = client.from("todos").select()
let todos: [Todo] = try await builder.execute(options: FetchOptions()).value

// After
let todos: [Todo] = try await builder.execute(options: FetchOptions(), decoder: nil).value
```

This is a compile error, not a silent behavior change, and only affects code that calls the
generic `execute(options:)` through `any`/`some PostgrestExecutableBuilder` rather than through a
concrete builder type such as `PostgrestFilterBuilder`.

## `RealtimeChannelV2.broadcast(event:message:)` gains a per-call `encoder:` override

`broadcast(event:message:)` now accepts a trailing `encoder: JSONEncoder? = nil`, overriding the
fixed internal encoder (`JSONValue.encoder`) previously always used to serialize `message`. Calling
`broadcast` without the new argument compiles unchanged and behaves the same as before.

```swift
try await channel.broadcast(event: "cursor", message: cursorPosition, encoder: mySnakeCaseEncoder)
```

## `Optional` no longer conforms to `PostgrestFilterValue`; `nil` cannot be a comparison operand

`Optional` used to conform to `PostgrestFilterValue`, rendering `nil` as the literal text `NULL`.
It now conforms only to the new `PostgrestArrayElement` protocol, so passing `nil` (or any
optional) to `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `like`, `ilike`, `in` or `notIn` no longer
compiles.

The old conformance produced silently wrong results rather than an error. Verified against a live
PostgREST 14.15: on an `integer` column `column=eq.null` is an HTTP 400, but on a `text` column it
returns **HTTP 200 with the row whose value is the literal string** `'null'` — a wrong row, not an
empty result. `column = NULL` is never true in SQL, so there is no correct query to send here and
the SDK does not guess one.

```swift
// Before — compiled, sent `email=eq.NULL`, matched the wrong rows
let email: String? = nil
try await client.from("users").select().eq("email", value: email).execute()

// After — use the NULL-aware filter
try await client.from("users").select().is("email", value: nil).execute()

// ...and its negation
try await client.from("users").select()
  .not("email", operator: .is, value: "null").execute()
```

**This is a compile error**, so the compiler lists every affected call site:
`argument type 'String?' does not conform to expected type 'PostgrestFilterValue'`. If the value is
optional only because of how you obtained it, unwrap it and branch:

```swift
let query = client.from("users").select()
let scoped = email.map { query.eq("email", value: $0) } ?? query.is("email", value: nil)
```

There is no escape hatch, and that is deliberate — the previous behavior had no correct use.

### Array columns still accept `NULL` members

A real Postgres array may legitimately contain `NULL`, so `Optional` keeps that capability through
`PostgrestArrayElement`:

```swift
// Still compiles, still sends `tags=cs.{a,NULL}`
try await client.from("users").select().contains("tags", value: [Optional("a"), nil]).execute()
```

### If you wrote your own `PostgrestFilterValue`

`PostgrestFilterValue` now refines `PostgrestArrayElement`, which has a default implementation for
every conforming type. Existing custom conformances keep compiling unchanged and gain array-element
support for free. Only declare `postgrestArrayElement` yourself if your type is a nested array
literal or a real `NULL`, where escaping the raw value as a scalar would be wrong.

## PostgREST's pre-v3 builders are now frozen under `Legacy/`

The builder API PostgREST shipped before v3 — `PostgrestClient`, `PostgrestQueryBuilder`,
`PostgrestFilterBuilder`, `PostgrestTransformBuilder`, `PostgrestRequestBuilder`, and the option
types beside them (`PostgrestResponse`, `CountOption`, `PostgrestReturningOptions`,
`TextSearchType`, `ExplainFormat`, `FetchOptions`) — moved from `Sources/PostgREST/` to
`Sources/PostgREST/Legacy/`. Not one symbol was renamed, retyped, or moved to a different module.

These builders each carry their own retry loop and their own escaping rules. v3 replaces them with
a value-typed core rather than rewriting them in place, and the directory boundary is what makes
"replace" honest: a bug reported against `Legacy/` is answered by pointing at the replacement, not
by patching code that is already scheduled for deletion.

```swift
// Before — and After. Identical.
let todos: [Todo] = try await client
  .from("todos")
  .select()
  .eq("is_done", value: false)
  .execute()
  .value
```

**This is neither a compile error nor a silent behavior change** — there is nothing in your code to
find or fix. What changed is the support commitment: these types stop receiving behavior fixes as
of this release, are marked `@available(*, deprecated, ...)` later in v3, and are removed in v4.
Read a `!` on this change as "the guarantee moved", not "your build breaks".

Nothing is withdrawn today, so there is no escape hatch to reach for. When the deprecation
warnings do arrive, the replacement is the typed API — `client.schema("public").from(Todo.self)`
and the `@Table` macro — not a different spelling of the same builder.

## `AuthError` gains `Kind.oauthFlowFailed`; client-side OAuth failures throw instead of trapping

`AuthError.Kind` has a new member:

```swift
static let oauthFlowFailed: AuthError.Kind
```

It covers redirect-based sign-in failures that happen entirely on the client: a redirect URL
that carried an error or no session (what v2 reported as `.pkce(_:)` and
`.invalidImplicitGrantFlowURL`), and two call sites in `signInWithOAuth(provider:redirectTo:scopes:queryParams:configure:)` (the
`ASWebAuthenticationSession` overload) used to end the process instead of throwing:

| Condition | Before | After |
| --- | --- | --- |
| No redirect URL with a scheme, from either `redirectTo` or `AuthClient.Configuration.redirectToURL` | `preconditionFailure` | throws `AuthError` with `kind == .oauthFlowFailed` |
| `ASWebAuthenticationSession` reports neither a URL nor an error | `fatalError` | `reportIssue`, then throws `AuthError` with `kind == .oauthFlowFailed` |

The redirect URL is read per call: `redirectTo` is a parameter of the sign-in method, falling back
to `AuthClient.Configuration.redirectToURL`. A value that varies per call is not something to trap
on, and the enclosing method already throws, so an error costs nothing. (A value fixed once at
construction is different — those still trap. See "When trapping is allowed" in `AGENTS.md`.)

This also restores something v3 dropped. `AuthError.invalidRedirectScheme` existed in v2 and was
listed above as removed with no replacement, on the grounds that it no longer represented anything
GoTrue could throw. That was right about the server and wrong about the client: the condition is
still real, it just belongs to the SDK rather than the API. Read that row as:

| Before | After |
| --- | --- |
| `AuthError.invalidRedirectScheme` | `AuthError` with `kind == .oauthFlowFailed` |

```swift
// Before — no way to handle this; the app died on the missing redirect URL
let session = try await supabase.auth.signInWithOAuth(provider: .github)

// After
do {
  let session = try await supabase.auth.signInWithOAuth(provider: .github)
} catch let error as AuthError where error.kind == .oauthFlowFailed {
  presentSetupError(error.message)
}
```

This is not a compile error. `Kind` is an open struct (see "`AuthError` is now a struct, not an
enum" below), so a new member is additive; a `switch` over `kind` already needs a `default`.

`errorCode` for this kind is `.unknown`, unless the redirect URL carried an `error_code`
parameter, in which case it is that value.

## `AuthError` is now a struct, not an enum

`AuthError` is a struct with `kind: AuthError.Kind`, `message`, `errorCode`,
`weakPasswordReasons`, `response` and `underlyingError`. `Kind` is a `RawRepresentable` struct
with static members: `.server`, `.sessionMissing`, `.oauthFlowFailed`, `.jwtVerificationFailed`,
`.refreshDiscarded`, `.transport` and `.decoding`. `AuthError.sessionMissing` still exists as a
static value, so `throw AuthError.sessionMissing` compiles unchanged.

`Kind` says which party failed, not why. The old `.api` and `.weakPassword` cases are both
`.server`; GoTrue's reason is in `errorCode`, and `weakPasswordReasons` is filled when
`errorCode == .weakPassword`. The old `.pkce(_:)` and `.invalidImplicitGrantFlowURL` cases are
both `.oauthFlowFailed`; the flow type is your own `AuthClient.Configuration.flowType`.

The package builds with library evolution enabled, so adding a case to a public enum was a
binary-breaking change; every new failure GoTrue learned to report needed a major version. The
`.api` case also carried an `HTTPURLResponse`, which is not `Sendable`. The struct is `Sendable`,
conforms to the new `SupabaseError` root, and carries the status, headers, body and Supabase
request id in `response`.

This is a compile error for every `case`-based pattern and for the removed `~=` operator:

| Before | After |
| --- | --- |
| `catch AuthError.sessionMissing` | `catch let error as AuthError where error.kind == .sessionMissing` |
| `catch let AuthError.api(message, code, data, response)` | `catch let error as AuthError where error.kind == .server` then `error.message`, `error.errorCode`, `error.response?.body`, `error.response?.statusCode` |
| `catch let AuthError.weakPassword(message, reasons)` | `catch let error as AuthError where error.errorCode == .weakPassword` then `error.weakPasswordReasons` |
| `catch let AuthError.pkceGrantCodeExchange(message, error, code)` | `error.kind == .oauthFlowFailed`; `message` is now `"<error>: <description>"` and `code` is in `error.errorCode` |
| `catch let AuthError.oauthFlowFailed(message)` | `error.kind == .oauthFlowFailed` then `error.message` |
| `catch let AuthError.jwtVerificationFailed(message)` | `error.kind == .jwtVerificationFailed` then `error.message` |
| `AuthError.sessionMissing ~= error` | `(error as? AuthError)?.kind == .sessionMissing` |

```swift
// Before
do {
  try await supabase.auth.signIn(email: email, password: password)
} catch let AuthError.api(message, errorCode, _, response) {
  print(response.statusCode, errorCode, message)
} catch AuthError.sessionMissing {
  showLogin()
}

// After
do {
  try await supabase.auth.signIn(email: email, password: password)
} catch let error as AuthError where error.kind == .server {
  print(error.response?.statusCode ?? 0, error.errorCode, error.message)
} catch let error as AuthError where error.kind == .sessionMissing {
  showLogin()
}
```

`AuthError` is no longer `Equatable`. `error == .sessionMissing` and any `Equatable` state type
that stores an `AuthError` stop compiling; compare `kind`, `errorCode` and `message`, or store
those instead. String interpolation prints `AuthError(server): Invalid login credentials [status
400, request ...]` instead of the case name.

`signOut` keeps swallowing 401, 403 and 404 responses from the `/logout` endpoint, whether or not the body was a recognizable GoTrue error. In v2 that fallback surfaced as `.api(message: "Unexpected error", ...)`; in v3 it is kind `.server` with `errorCode == .unexpectedFailure`. No change in behavior.

The internal `WebAuthnError` type, which could leak from the passkey and WebAuthn MFA flows, is
folded into `AuthError` with kind `.decoding`: every case was a payload the SDK could not
interpret, either from GoTrue or from the platform authenticator.

## `fetch:` closures and `StorageHTTPSession` replaced by `ClientTransport` and `ClientMiddleware`

Every sub-client now sends through one protocol, `ClientTransport`, behind an ordered chain of
`ClientMiddleware`. The two travel together in one value, `HTTPClientConfiguration`, which every
client takes as a single `http:` parameter. `AuthClient`, `PostgrestClient` and `FunctionsClient`
take `http:` directly, where they used to take a `fetch:` closure; `SupabaseStorageClient` and
`RealtimeClientV2` receive the same value through `StorageClientConfiguration` and
`RealtimeClientOptions`, which replace `StorageHTTPSession` and Realtime's `fetch:` closure.
`SupabaseClient` gains `SupabaseClientOptions.GlobalOptions.http`, which it hands to every
sub-client at once. All five types — `HTTPClientConfiguration`, `ClientTransport`,
`ClientMiddleware`, `URLSessionTransport` and the streaming `HTTPBody` — are public in `Helpers`,
which every module re-exports, so `import Supabase` (or `import Auth`, `import Storage`, …) is
enough.

### Why

v2 had four incompatible injection shapes for the same job. `AuthClient.FetchHandler`,
`PostgrestClient.FetchHandler` and `FunctionsClient.FetchHandler` were three separate
`typealias` declarations over the identical
`(URLRequest) async throws -> (Data, URLResponse)` signature; Storage had
`StorageHTTPSession` with its own `fetch`/`upload` pair; Realtime had a bare
`RealtimeClientOptions.fetch` closure. None of them composed. There was no way to add logging, a
custom header, retry, or a mock to every sub-client at once — you wrote the same closure five
times, or you wrote it once and it still did not cover Storage's upload path. And a closure that
returns `Data` cannot stream: a 2 GB download was a 2 GB allocation.

One `Sendable` transport protocol plus a middleware chain is where the ecosystem landed —
Apple's swift-openapi-runtime, Smithy Swift, and Apollo iOS all expose that exact pair. This SDK
now matches it, and `HTTPBody` gives the transport a body it can hand back before it is complete.

### Before / After

Auth, PostgREST and Functions each took a `fetch:` closure:

```swift
// Before
let session = URLSession(configuration: configuration)

let auth = AuthClient(
  url: authURL,
  localStorage: localStorage,
  fetch: { try await session.data(for: $0) }
)
let database = PostgrestClient(
  url: databaseURL,
  fetch: { try await session.data(for: $0) }
)
let functions = FunctionsClient(
  url: functionsURL,
  fetch: { try await session.data(for: $0) }
)
```

```swift
// After
let session = URLSession(configuration: configuration)
let transport = URLSessionTransport(session: session)

let auth = AuthClient(
  url: authURL,
  localStorage: localStorage,
  http: .init(transport: transport)
)
let database = PostgrestClient(
  url: databaseURL,
  http: .init(transport: transport)
)
let functions = FunctionsClient(
  url: functionsURL,
  http: .init(transport: transport)
)
```

`AuthClient.Configuration` and `PostgrestClient.Configuration` changed the same way: the `fetch:`
parameter and stored property became `http:`.

Storage swapped `StorageHTTPSession` for the same transport:

```swift
// Before
let storage = SupabaseStorageClient(
  configuration: StorageClientConfiguration(
    url: storageURL,
    headers: headers,
    session: StorageHTTPSession(session: session)
  )
)
```

```swift
// After
let storage = SupabaseStorageClient(
  configuration: StorageClientConfiguration(
    url: storageURL,
    headers: headers,
    http: .init(transport: URLSessionTransport(session: session))
  )
)
```

Realtime's `fetch:` — used for REST broadcast calls — became `http:`:

```swift
// Before
let options = RealtimeClientOptions(fetch: { try await session.data(for: $0) })

// After
let options = RealtimeClientOptions(http: .init(transport: URLSessionTransport(session: session)))
```

And on `SupabaseClient`, one transport and one middleware chain now cover every sub-client:

```swift
let client = SupabaseClient(
  supabaseURL: supabaseURL,
  supabaseKey: supabaseKey,
  options: SupabaseClientOptions(
    global: SupabaseClientOptions.GlobalOptions(
      http: HTTPClientConfiguration(
        transport: URLSessionTransport(session: session),
        middlewares: [AppVersionMiddleware()]
      )
    )
  )
)
```

**This is a compile error.** The parameters and types below were removed, not deprecated, so the
compiler points at every call site.

| Before | After |
| --- | --- |
| `AuthClient.FetchHandler` | `any ClientTransport` |
| `PostgrestClient.FetchHandler` | `any ClientTransport` |
| `FunctionsClient.FetchHandler` | `any ClientTransport` |
| `StorageHTTPSession` | `any ClientTransport` |
| `AuthClient(… fetch:)`, `AuthClient.Configuration(… fetch:)` | `http:` |
| `PostgrestClient(… fetch:)`, `PostgrestClient.Configuration(… fetch:)` | `http:` |
| `FunctionsClient(… fetch:)` | `http:` |
| `StorageClientConfiguration(… session:)` | `StorageClientConfiguration(… http:)` |
| `RealtimeClientOptions(… fetch:)` | `RealtimeClientOptions(… http:)` |

### The escape hatch

`URLSessionTransport(session:)` wraps any `URLSession` you already have — delegate, configuration,
certificate pinning and all — so a v2 `fetch: { try await session.data(for: $0) }` becomes
`http: .init(transport: URLSessionTransport(session: session))` with nothing else to change. There is also
`URLSessionTransport(configuration:)`, which builds its own session from a
`URLSessionConfiguration`.

### Writing a middleware

A middleware sees the request on the way out and the response on the way back. Call `next` exactly
once to continue, or return without calling it to short-circuit:

```swift
struct AppVersionMiddleware: ClientMiddleware {
  static let headerName = HTTPField.Name("X-App-Version")!

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    next: nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws
      -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var request = request
    request.headerFields[Self.headerName] = "2.1.0"
    return try await next(request, body)
  }
}
```

Middlewares run in array order on the way out and in reverse on the way back. A middleware that
retries must check `HTTPBody.iterationBehavior` and skip the retry when it is `.single`.

### Mocking the network in tests

A transport is one method, so a stub is five lines:

```swift
struct StubTransport: ClientTransport {
  func send(_ request: HTTPRequest, body: HTTPBody?) async throws -> (HTTPResponse, HTTPBody?) {
    (HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
  }
}
```

Pass it as `http: .init(transport: StubTransport())` to any sub-client, or as
`GlobalOptions.http` to replace the network for the whole client.

### Behavior notes

- **Your middlewares run before the SDK's.** `SupabaseClient` appends its own middlewares — trace
  context, and the one that injects the bearer token — *after* yours. So a middleware you supply
  sees the request without the `Authorization` header, while your `ClientTransport` always sees the
  final request, token included. Read or rewrite auth headers in a transport, not a middleware.
- **A caller-supplied Realtime transport opts out of the SDK's middlewares.** If you set
  `RealtimeClientOptions.http.transport` yourself, `SupabaseClient` installs none of its own middlewares
  on Realtime — it assumes you are fully in charge of that path. Leave it `nil` to get the global
  transport plus the SDK's chain.
- **Error and response types no longer carry an `HTTPURLResponse`.** `PostgrestResponse.response`
  carries the `HTTPTypes` response head instead, and every module error carries an
  `HTTPErrorResponse` (status, headers and body); see the sections on those types below.
- **Functions streaming goes through your transport now.** `_invokeWithStreamedResponse` used to
  run on a private `URLSession` that ignored everything you configured. It now sends through the
  client's `http` transport and middlewares, like every other call.
- **A streamed `FunctionsError` with kind `.server` now carries the response body.** In v2 the
  streamed call threw `.httpError(code, Data())`; the body is now in `response?.body`, so anything
  that read the payload from a non-2xx streamed invoke no longer has to special-case an empty
  `Data`.
- **Streamed chunk boundaries changed.** The default transport yields one chunk per
  `URLSession` data delivery, so boundaries follow the network, not the payload: an SSE event can
  arrive split across chunks or several events can share one. Code that assumed one chunk per
  `write` on the server, or one chunk per event, must reassemble on the `\n\n` frame separator.
- **`HTTPTypes` names are now in scope.** `Helpers` re-exports `HTTPTypes`, so `import Supabase`
  (or `import Functions`, `import Auth`, …) also brings `HTTPRequest`, `HTTPResponse`, `HTTPFields`
  and `HTTPField` in. If you also import another library that exports those names, the reference
  becomes ambiguous — qualify it with the module name (`HTTPTypes.HTTPRequest`).
- **Timeouts belong to the transport.** The SDK always sets `URLRequest.timeoutInterval` itself —
  `HTTPClientConfiguration.timeout` when set, otherwise 60 seconds (150 for Functions) — so on
  the default transport `URLSessionConfiguration.timeoutIntervalForRequest` no longer takes effect
  for SDK requests. Set the idle timeout per client with
  `GlobalOptions(http: .init(timeout: .seconds(30)))` (or the `http:` parameter of any standalone
  sub-client), and per call with `FunctionInvokeOptions.timeout` or
  `PostgrestRequestBuilder.timeout(_:)`. A custom `ClientTransport` owns its own timeout policy
  and is free to ignore both.

## `SupabaseClientOptions.GlobalOptions.session` is removed

`GlobalOptions` no longer has a `session: URLSession` property or init parameter. The `URLSession`
that HTTP requests go through is configured on the transport instead: pass
`URLSessionTransport(session:)` as `GlobalOptions.http.transport`.

With `http` in place, `session` had two overlapping jobs. It backed the default transport only
while `http.transport` was `nil`, so a caller who set both a custom `session` and a custom
`transport` silently lost the session for HTTP. It was also copied into
`RealtimeClientOptions.session` for the WebSocket, which is not an HTTP request and never goes
through `ClientTransport`. One knob now configures HTTP, and Realtime's WebSocket session is
configured only where it lives.

```swift
// Before
let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(global: .init(session: mySession))
)

// After
let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(global: .init(http: .init(transport: URLSessionTransport(session: mySession))))
)
```

This is a compile error: `GlobalOptions.init` has no `session:` argument, and
`options.global.session` no longer exists.

One behavior change compiles without change elsewhere: Realtime no longer inherits a `URLSession`
from `GlobalOptions`. If you relied on the global session reaching Realtime's WebSocket (for
example for certificate pinning), pass it on the Realtime options instead:

```swift
options: .init(
  global: .init(http: .init(transport: URLSessionTransport(session: mySession))),
  realtime: .init(session: mySession)
)
```

## `PostgrestResponse.response` and `FunctionsClient.invoke(decode:)` carry `HTTPResponse` instead of `HTTPURLResponse`

Every place the SDK handed you the raw response head now uses `HTTPTypes.HTTPResponse` — the
same type a `ClientTransport` or `ClientMiddleware` produces:

| Before | After |
| --- | --- |
| `PostgrestResponse.response: HTTPURLResponse` | `PostgrestResponse.response: HTTPResponse` |
| `PostgrestResponse(data:response: HTTPURLResponse, value:)` | `PostgrestResponse(data:response: HTTPResponse, value:)` |
| `AuthError.api(message:errorCode:underlyingData:underlyingResponse: HTTPURLResponse)` | `AuthError.response: HTTPErrorResponse?` (see "`AuthError` is now a struct, not an enum") |
| `FunctionsClient.invoke(_:options:decode: (Data, HTTPURLResponse) throws -> T)` | `FunctionsClient.invoke(_:options:decode: (Data, HTTPResponse) throws -> T)` |

### Why

Since the transport seam landed (previous section), the SDK's network layer speaks `HTTPTypes`
end to end. The only reason an `HTTPURLResponse` still existed was to fill these four public
signatures, and the SDK had to synthesize one from the `HTTPTypes` head on every response, with a
`url` that was the request URL rather than anything the server sent. A custom `ClientTransport`
that never touches `URLSession` (AsyncHTTPClient on Linux, a test stub) paid that cost for
nothing, and Foundation's `HTTPURLResponse` was the one type in these signatures that a
non-Foundation networking stack could not produce natively.

### Before / After

`HTTPResponse` has `status` (an `HTTPResponse.Status` with `code` and `reasonPhrase`) and
`headerFields` (an `HTTPFields`, subscripted by `HTTPField.Name`). It has no URL. `HTTPError`
itself is gone (see "`HTTPError` removed" below); each module error carries an
``HTTPErrorResponse`` with the same shape plus the body.

```swift
// Before
do {
  try await supabase.storage.from("avatars").remove(paths: ["a.png"])
} catch let error as HTTPError {
  print(error.response.statusCode)
  print(error.response.allHeaderFields["Content-Type"] as? String)
  print(error.response.url)
}

// After
do {
  try await supabase.storage.from("avatars").remove(paths: ["a.png"])
} catch let error as StorageError {
  print(error.response?.statusCode)
  print(error.response?.headers[.contentType])
  // No URL on the response; log the URL you requested instead.
}
```

```swift
// Before
let response = try await supabase.from("todos").select().execute()
let etag = response.response.value(forHTTPHeaderField: "ETag")

// After
let response = try await supabase.from("todos").select().execute()
let etag = response.response.headerFields[.eTag]
```

```swift
// Before
} catch let AuthError.api(_, _, _, response) where response.statusCode == 429 {

// After
} catch let error as AuthError where error.response?.statusCode == 429 {
```

```swift
// Before
let payload = try await supabase.functions.invoke("hello") { data, response in
  guard response.statusCode == 200 else { throw MyError.unexpected }
  return try JSONDecoder().decode(Payload.self, from: data)
}

// After
let payload = try await supabase.functions.invoke("hello") { data, response in
  guard response.status == .ok else { throw MyError.unexpected }
  return try JSONDecoder().decode(Payload.self, from: data)
}
```

### Compile error or silent?

Compile error. `HTTPResponse` has none of `statusCode`, `allHeaderFields`, `url`,
`value(forHTTPHeaderField:)` or `mimeType`, so every read of those on one of these values fails
to build. `PostgrestResponse.status` (the `Int` status code) is unchanged. Search your code for
`.response.statusCode`, `.response.allHeaderFields`, `.response.url` and `underlyingResponse` to
find the sites.

### Escape hatch

There is no way to get an `HTTPURLResponse` back from these types. If a dependency needs one,
build it from the head:

```swift
guard let urlResponse = HTTPURLResponse(httpResponse: response.response, url: requestURL) else {
  return
}
```

The initializer is failable, so unwrap its result before handing it to an API that wants a
non-optional `HTTPURLResponse`.

`HTTPURLResponse.init(httpResponse:url:)` comes from `HTTPTypesFoundation`, which `Helpers` now
re-exports alongside `HTTPTypes`.

## `FunctionsError` is now a struct, not an enum

`FunctionsError` is a struct with a `kind: FunctionsError.Kind` property instead of an enum with
`.relayError` and `.httpError(code:data:)` cases. `Kind` is a `RawRepresentable` struct with
static members: `.relay`, `.server`, `.transport` and `.decoding`.

The package builds with library evolution enabled, so adding a case to a public enum was a
binary-breaking change. Every new failure the SDK learned to report would have needed a major
version. A struct with an open `Kind` grows additively. The struct also conforms to
`SupabaseError`, the new root shared by every module, and carries the HTTP status, headers, body
and Supabase request id in `response`.

This is a compile error: pattern matching on the old cases no longer compiles.

```swift
// Before
do {
  try await supabase.functions.invoke("hello")
} catch FunctionsError.relayError {
  retryLater()
} catch let FunctionsError.httpError(code, data) {
  print(code, String(decoding: data, as: UTF8.self))
}

// After
do {
  try await supabase.functions.invoke("hello")
} catch let error as FunctionsError where error.kind == .relay {
  retryLater()
} catch let error as FunctionsError where error.kind == .server {
  let response = error.response!  // always set for `.server` and `.relay`
  print(response.statusCode, String(decoding: response.body, as: UTF8.self), response.requestID ?? "")
}
```

`FunctionsError` is not `Equatable`. Compare `kind`, `message` and `response` instead. String
interpolation of the error now prints `FunctionsError(server): Edge Function returned a non-2xx
status code: 500 [status 500]` instead of the case name.

## Network and decoding failures are wrapped in the module error

Auth, PostgREST, Storage, Functions and Realtime no longer let `URLError` and `DecodingError`
propagate as themselves. A `URLError` from the network layer is thrown as the module error with
kind `.transport`, and a success body that cannot be decoded throws it with kind `.decoding`.
Errors thrown by your own code that runs inside the request — a custom `ClientTransport` or
`ClientMiddleware`, or the `accessToken` closure — still propagate as themselves. The original
error is in `underlyingError`. `CancellationError` is never wrapped and still propagates as
itself.

Cancelling a request is the case worth spelling out. `URLSession`'s async APIs do not throw
`CancellationError` when the enclosing `Task` is cancelled — they throw `URLError(.cancelled)`,
which is a `URLError` like any other and so is wrapped as `.transport`. A `catch is
CancellationError` does not match a cancelled request; check the code on `underlyingError`
instead:

```swift
// Before
} catch is CancellationError {
  // the user cancelled — no error banner
}

// After
} catch let error as any SupabaseError
  where (error.underlyingError as? URLError)?.code == .cancelled {
  // the user cancelled — no error banner
}
```

This also compiles silently — the old `catch` block simply stops being reached. Search for `is
CancellationError` near Supabase calls. A cancelled request is never retried.

Without this, one `catch let error as any SupabaseError` missed exactly the failures a user is
most likely to hit in the field: no network, and a schema drift between the app's model and the
server. swift-openapi-runtime and Auth0 wrap the same way.

This compiles silently. Search your codebase for `as URLError`, `as? URLError`, `as
DecodingError` and `as? DecodingError` near Supabase calls; those branches stop matching.

```swift
// Before
} catch let error as URLError where error.code == .notConnectedToInternet {
  showOfflineBanner()
}

// After
} catch let error as any SupabaseError where error.underlyingError is URLError {
  if (error.underlyingError as? URLError)?.code == .notConnectedToInternet {
    showOfflineBanner()
  }
}
```

There is no escape hatch that restores the raw error; `underlyingError` is the original value.

## `StorageError` gains `kind` and `response`; `statusCode` and `error` move to `serverError`

`StorageError` is no longer the decoded error body itself. It is a struct with `kind`,
`message`, `serverError`, `response` and `underlyingError`. The body Storage sends is decoded
into `StorageError.ServerError`, which keeps the wire fields `statusCode: String?`,
`error: String?` and `message`. `StorageError` no longer conforms to `Decodable`.

Storage used to throw two unrelated types for a failed request: `StorageError` when the body was
a recognizable payload, and `HTTPError` otherwise. Neither carried the response headers or the
Supabase request id, and `statusCode` was a string. Now every failure is a `StorageError`, the
integer status lives in `response?.statusCode`, and `response?.requestID` is available for
support tickets.

This is a compile error: `statusCode` and `error` no longer exist on `StorageError`, and
`JSONDecoder().decode(StorageError.self, ...)` no longer compiles.

```swift
// Before
} catch let error as StorageError {
  if error.statusCode == "404" { showMissing() }
  print(error.error ?? "", error.message)
} catch let error as HTTPError {
  print(error.response.statusCode)
}

// After
} catch let error as StorageError {
  if error.response?.statusCode == 404 { showMissing() }
  print(error.serverError?.error ?? "", error.message)
}
```

Kinds: `.server` for any non-2xx (`serverError` is set when the body was a recognizable Storage
payload, `nil` otherwise; the raw bytes are always in `response?.body`), `.transport`, `.decoding`,
and `.invalidRequest` for the URL-building helpers such as `publicURL`, which threw
`URLError(.badURL)` before.

## `PostgrestError` gains `kind` and `response`; server fields move to `serverError`

`PostgrestError` is a wrapper with `kind`, `message`, `serverError`, `response` and
`underlyingError`. The body PostgREST returns is decoded into `PostgrestError.ServerError`, which
keeps `code`, `message`, `details` and `hint`. `PostgrestError` itself is no longer `Decodable`.

A failed query used to arrive as one of three unrelated types: `PostgrestError` for a recognized
body, `HTTPError` for anything else, and a raw `DecodingError` when the rows did not match your
model. None carried the response headers or the Supabase request id. Now every failure is a
`PostgrestError`, and `response?.requestID` is there for support tickets.

This is a compile error: `code`, `details` and `hint` no longer exist on `PostgrestError`.

```swift
// Before
} catch let error as PostgrestError {
  if error.code == "23505" { showDuplicate(error.details) }
} catch let error as HTTPError {
  print(error.response.statusCode)
}

// After
} catch let error as PostgrestError {
  if error.serverError?.code == "23505" { showDuplicate(error.serverError?.details) }
  print(error.response?.statusCode ?? 0, error.response?.requestID ?? "")
}
```

Kinds: `.server` for any non-2xx (`serverError` is set when the body was a recognizable PostgREST
payload, `nil` otherwise; the raw bytes are always in `response?.body`), `.transport`, `.decoding`
(also for a 2xx the SDK cannot use, such as a `count(_:)` reply with no `Content-Range`), and
`.invalidRequest` for client-side rejections such as `.csv()` combined with `.stripNulls()`.

If you constructed `PostgrestError(message:)` yourself, pass a kind:
`PostgrestError(kind: .invalidRequest, message:)`.

## `HTTPError` removed

The generic `HTTPError` type is gone. Storage and PostgREST threw it when a non-2xx body did not
decode as their own error payload, which meant two catch clauses per module. Each module error
now carries `response: HTTPErrorResponse?` with the status code, `HTTPFields` headers, raw body
and `requestID`, and an unrecognized body is reported with kind `.server` and `serverError == nil`.

This is a compile error for any `catch let error as HTTPError`.

```swift
// Before
} catch let error as HTTPError {
  print(error.response.statusCode, String(decoding: error.data, as: UTF8.self))
}

// After
} catch let error as any SupabaseError where error.response != nil {
  let response = error.response!
  print(response.statusCode, String(decoding: response.body, as: UTF8.self))
}
```

`HTTPErrorResponse.headers` is `HTTPFields` from swift-http-types, not `[String: String]`.
`import HTTPTypes` to spell header names: `response.headers[.contentType]`.

## Realtime throws `RealtimeError` for every failure

`RealtimeError` is now public. It is a struct with `kind: RealtimeError.Kind`, `message`,
`response` and `underlyingError`, conforming to `SupabaseError`. Kinds: `.transport`,
`.timeout`, `.accessTokenMissing`, `.maxRetryAttemptsReached`, `.channelClosedByServer`,
`.server` and `.decoding`.

Before, `RealtimeError` was `package`-scoped, so `subscribeWithError()` and `httpSend` handed you
an `any Error` you could only inspect through `localizedDescription`. `httpSend` could also leak
an internal `TimeoutError`, and connection failures surfaced as an internal `WebSocketError`
wrapping a placeholder `NSError(domain: "ConnectionManager", code: -1)`. All of those are now
`RealtimeError`.

This compiles silently. Search your codebase for `localizedDescription` comparisons and
`NSError` domain checks around `subscribeWithError()` and `httpSend`, and switch them to `kind`:

```swift
// Before
do {
  try await channel.subscribeWithError()
} catch {
  if error.localizedDescription == "Maximum retry attempts reached." { scheduleRetry() }
}

// After
do {
  try await channel.subscribeWithError()
} catch let error as RealtimeError where error.kind == .maxRetryAttemptsReached {
  scheduleRetry()
}
```

For `httpSend`, a non-202 answer is `.server` with `response?.statusCode` and `response?.body`
set; a request that never completes is `.transport` with the `URLError` in `underlyingError`.
A WebSocket that could not be opened, or closed before it was ready, is also `.transport`: the
recovery is the same (retry, check connectivity), so it does not get a kind of its own.

## OAuth server fields the API leaves out are now optional

`OAuthClient.clientName`, `OAuthAuthorizationClient.name`, `OAuthAuthorizationUser.email` and
`OAuthAuthorizationDetails.scope` are `String?` rather than `String`.

Auth marks all four `omitempty`, so it drops the key instead of sending an empty string. One
client registered without a name, or one user who signed up by phone, anonymously or with Web3,
was enough to fail the whole response: `getClient` threw a decoding error, and
`getAuthorizationDetails` threw an opaque aggregate error, since neither the consent shape nor the
redirect shape could decode.

This is a compile error wherever you read one of the four as a non-optional `String`.

```swift
// Before
Text(details.client.name)
Text(details.user.email)

// After
Text(details.client.name ?? "Unnamed app")
Text(details.user.email ?? "No email on file")
```

## `OAuthClient` array fields the API leaves out are now optional

`OAuthClient.redirectUris` is `[String]?`, `OAuthClient.grantTypes` is `[OAuthClientGrantType]?`
and `OAuthClient.responseTypes` is `[OAuthClientResponseType]?`.

Auth marks all three `omitempty`, and Go drops an `omitempty` slice from the JSON when it is empty
as well as when it is nil, so a client holding none of them sends no key at all. Every call
returning an `OAuthClient` threw a decoding error on such a client: `listClients`, `createClient`,
`getClient`, `updateClient` and `regenerateClientSecret`.

`OAuthGrant.scopes` is unaffected: Auth sends it without `omitempty`, so the key is always there.

This is a compile error wherever you read one of the three as a non-optional array.

```swift
// Before
let uris = client.redirectUris
let supportsRefresh = client.grantTypes.contains(.refreshToken)

// After
let uris = client.redirectUris ?? []
let supportsRefresh = client.grantTypes?.contains(.refreshToken) ?? false
```

## `FunctionInvokeOptions.timeoutInterval` is now `timeout: Duration`

`FunctionInvokeOptions` takes `timeout: Duration? = nil` instead of `timeoutInterval: TimeInterval?
= nil` in all four initializers, and `FunctionsClient.requestIdleTimeout` is a `Duration`
(`.seconds(150)`) instead of a `TimeInterval` (`150`).

The SDK-wide request timeout that lands alongside this change (`HTTPClientConfiguration.timeout`,
`PostgrestRequestBuilder.timeout(_:)`) is a `Duration`, the Swift standard library's unit-safe
time type. The Functions per-invocation override shares the same resolution path, so it takes the
same type; keeping it a `TimeInterval` would have left callers converting between `Double` seconds
and `Duration` inside one request. The remaining `TimeInterval` intervals in the public API
(Realtime's heartbeat, reconnect and reply timeouts) move the same way; see the next section.

```swift
// Before
try await supabase.functions.invoke(
  "slow-report",
  options: .init(timeoutInterval: 30)
)
let fallback: TimeInterval = FunctionsClient.requestIdleTimeout

// After
try await supabase.functions.invoke(
  "slow-report",
  options: .init(timeout: .seconds(30))
)
let fallback: Duration = FunctionsClient.requestIdleTimeout
```

This is a compile error: the `timeoutInterval:` argument label no longer exists, and a
`TimeInterval` value no longer type-checks where `requestIdleTimeout` is used. Search for
`timeoutInterval:` at `FunctionInvokeOptions` call sites and for `requestIdleTimeout`.

## Realtime intervals are now `Duration`, and `timeoutInterval` is `timeout`

Every interval on `RealtimeClientOptions` is a `Duration` instead of a `TimeInterval`, and the
reply timeout is renamed:

| Before | After |
|---|---|
| `heartbeatInterval: TimeInterval` | `heartbeatInterval: Duration` |
| `reconnectDelay: TimeInterval` | `reconnectDelay: Duration` |
| `timeoutInterval: TimeInterval` | `timeout: Duration` |
| `disconnectOnEmptyChannelsAfter: TimeInterval` | `disconnectOnEmptyChannelsAfter: Duration` |
| `defaultHeartbeatInterval: TimeInterval` (`25`) | `defaultHeartbeatInterval: Duration` (`.seconds(25)`) |
| `defaultReconnectDelay: TimeInterval` (`7`) | `defaultReconnectDelay: Duration` (`.seconds(7)`) |
| `defaultTimeoutInterval: TimeInterval` (`10`) | `defaultTimeout: Duration` (`.seconds(10)`) |
| `defaultDisconnectOnEmptyChannelsAfter: TimeInterval` (`50`) | `defaultDisconnectOnEmptyChannelsAfter: Duration` (`.seconds(50)`) |

The per-call `timeout:` parameter on `RealtimeChannelV2.httpSend(event:message:timeout:)` (both
overloads) and `httpSend(event:data:timeout:)` is a `Duration?` instead of a `TimeInterval?`.

The `@_disfavoredOverload` `RealtimeClientOptions` initializer without `protocolVersion:` is
removed. The primary initializer defaults every argument it took, so every call that compiled
against it still compiles against the primary one once the intervals above are updated.

The request timeout (`HTTPClientConfiguration.timeout`, `PostgrestRequestBuilder.timeout(_:)`,
`FunctionInvokeOptions.timeout`) is already a `Duration`. Realtime was the last module that took
intervals as `Double` seconds, so one app could configure its HTTP timeout as `.seconds(30)` and
its Realtime timeout as `30` next to each other. `timeout` matches the name those APIs use.

```swift
// Before
let options = RealtimeClientOptions(
  heartbeatInterval: 30,
  reconnectDelay: 5,
  timeoutInterval: 15,
  disconnectOnEmptyChannelsAfter: 0
)
try await channel.httpSend(event: "ping", message: ["n": 1], timeout: 3)

// After
let options = RealtimeClientOptions(
  heartbeatInterval: .seconds(30),
  reconnectDelay: .seconds(5),
  timeout: .seconds(15),
  disconnectOnEmptyChannelsAfter: .zero
)
try await channel.httpSend(event: "ping", message: ["n": 1], timeout: .seconds(3))
```

This is a compile error at every call site that passes a literal or a `TimeInterval`, and wherever
a `default*` constant is used as a `TimeInterval`. Search for `timeoutInterval:`,
`defaultTimeoutInterval`, and `RealtimeClientOptions(`. If you hold the value as `TimeInterval`
seconds, convert it with `.seconds(value)` (`Duration.seconds(_:)` accepts a `Double`).

## `URLSessionTransport` no longer follows a 307/308 redirect for a one-shot request body

On Apple platforms, a request whose body is `HTTPBody.IterationBehavior.single` and that receives
a `307 Temporary Redirect` or `308 Permanent Redirect` now returns that redirect response to the
caller instead of following it. Every other body kind, and every other redirect status, is
followed as before. Linux is unchanged: it spools the body to disk before sending, so the copy can
be resent and the redirect is followed.

**Why**: request bodies are now streamed to `URLSession` as they are produced instead of being
buffered into memory first. A 307/308 keeps the method and resends the body, and a `.single`
body cannot be produced a second time. Failing the request halfway through with
`HTTPBodyAlreadyConsumedError` would hide what actually happened, so the transport hands the
redirect back the same way Go's `net/http` does for a non-rewindable body. Only bodies you build
with `HTTPBody(_:length:iterationBehavior: .single)` are affected; `HTTPBody(_ data:)` and
`HTTPBody(fileURL:)` are `.multiple` and replay.

```swift
// Before — the 307 was followed and the body resent from the buffered copy
let body = HTTPBody(chunks, length: .known(size), iterationBehavior: .single)
let (head, _) = try await transport.send(request, body: body)
head.status  // 200, from the redirect target

// After — the 307 itself comes back
let (head, _) = try await transport.send(request, body: body)
head.status  // 307; `head.headerFields[.location]` names the target
```

This is a behavior change, not a compile error. Search for `iterationBehavior: .single` on a
request body; if that endpoint can redirect with 307/308, either send the request to the final
URL directly or make the body `.multiple` by giving it a sequence that can be iterated again.

The same change also means a `.single` body whose `length` is `.known(n)` must yield exactly `n`
bytes: the count goes out as `Content-Length` before the body is read, and a mismatch now fails
the request with the new `HTTPBodyLengthMismatchError` instead of stalling until the request
timeout (too few bytes) or truncating on the server (too many).

## Auth and PostgREST retries share one implementation: jittered backoff and `Retry-After`

Auth and PostgREST — the two modules that already retried — now do so through one middleware
driven by an internal `RetryPolicy`. It runs outermost, so a replayed attempt re-runs your
`ClientMiddleware`s and resolves a fresh access token instead of reusing the first attempt's.
Storage and Functions are unchanged: they do not retry.

- **PostgREST** is unchanged in what it retries: GET and HEAD only, on a transient network
  failure or a 503/520, up to three retries. `retryEnabled`, `retry(enabled:)` and `db.retry`
  stay as they were. What changes is the wait: a random duration in `cap/2...cap` with
  `cap = min(30s, 1s · 2^n)` instead of a fixed `2^n` seconds, and a `Retry-After` header is
  honoured up to 30 s. Only a transient `URLError` (timeout, connection lost, DNS failure and the
  like) is retried; PostgREST used to retry any error thrown by a custom `ClientTransport`,
  `ClientMiddleware` or `accessToken` closure too.
- **Auth** makes 3 attempts instead of 2, with the same jittered wait (500 ms base, 20 s cap)
  instead of a fixed `0.5 · 2^n` seconds. What it retries is unchanged: GET, HEAD, OPTIONS, PUT,
  DELETE and POST (so token refreshes are replayed), on a transient `URLError` or a 408, 500,
  502, 503, 504 or Cloudflare 520–524/530.
- **Both** report a cancelled task as `CancellationError`, even when the transport reported it
  as `URLError.cancelled`.
- **Realtime** reconnects carry the same equal jitter, capped at 30 s: the first attempt waits
  between half of `reconnectDelay` and `reconnectDelay`, never longer than before.

Without jitter every client that lost the same connection retried at the same instant, and the
two modules had their own idea of a transient failure. This follows the AWS/Smithy retry
guidance.

```swift
// A middleware passed through `SupabaseClientOptions.GlobalOptions.http`:
struct RequestCounter: ClientMiddleware {
  let count: LockIsolated<Int>
  func intercept(
    _ request: HTTPRequest, body: HTTPBody?,
    next: nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws
      -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    count.withValue { $0 += 1 }
    return try await next(request, body)
  }
}

// Before — one `intercept` per `execute()`, even when PostgREST retried the request.
// After — one `intercept` per attempt, up to four for a PostgREST GET that keeps getting a 503.
try await supabase.from("todos").select().execute()
```

This compiles silently. Search your codebase for `ClientTransport` and `ClientMiddleware`
conformances — they now run once per attempt — and, in Auth or PostgREST error handling, for
code that expected a cancelled request to surface as `AuthError` or `PostgrestError`; it now
throws `CancellationError`. If you relied on PostgREST retrying a custom transport error, handle
the retry in your transport.

## `get`-prefixed accessors drop the prefix

Twelve public methods that only fetch a value lost their `get` prefix, per the Swift API Design
Guidelines rule that a method without side effects reads as a noun phrase.

| Before | After |
| --- | --- |
| `AuthAdmin.getUserById(_:)` | `AuthAdmin.user(id:)` |
| `AuthAdminOAuth.getClient(clientId:)` | `AuthAdminOAuth.client(id:)` |
| `AuthMFA.getAuthenticatorAssuranceLevel()` | `AuthMFA.authenticatorAssuranceLevel()` |
| `AuthClient.getOAuthSignInURL(...)` | `AuthClient.oauthSignInURL(...)` |
| `AuthClient.getLinkIdentityURL(...)` | `AuthClient.linkIdentityURL(...)` |
| `AuthClient.getClaims(...)` | `AuthClient.claims(...)` |
| `AuthOAuthServer.getAuthorizationDetails(...)` | `AuthOAuthServer.authorizationDetails(id:)` |
| `AuthClient.getPasskeyRegistrationOptions()` | `AuthClient.passkeyRegistrationOptions()` |
| `AuthClient.getPasskeyAuthenticationOptions()` | `AuthClient.passkeyAuthenticationOptions()` |
| `SupabaseStorageClient.getBucket(_:)` | `SupabaseStorageClient.bucket(_:)` |
| `StorageVectorsClient.getBucket(_:)` | `StorageVectorsClient.bucket(_:)` |
| `VectorBucketClient.getIndex(_:)` | `VectorBucketClient.indexDetails(_:)` |
| `VectorIndexClient.getVectors(keys:returnMetadata:)` | `VectorIndexClient.vectors(keys:returnMetadata:)` |
| `StorageFileApi.getPublicURL(...)` | `StorageFileApi.publicURL(...)` |

```swift
// Before
let user = try await supabase.auth.admin.getUserById(id)
let url = try supabase.storage.from("avatars").getPublicURL(path: "me.png")

// After
let user = try await supabase.auth.admin.user(id: id)
let url = try supabase.storage.from("avatars").publicURL(path: "me.png")
```

`getIndex(_:)` is the one that did not simply lose its prefix: `VectorBucketClient` already has an
`index(_:)` returning a `VectorIndexClient` handle, so a second `index(_:)` returning a
`VectorIndex` would have made `try await bucket.index("embeddings")` ambiguous. It is
`indexDetails(_:)` instead, which also reads closer to what it returns.

These are all compile errors. Search for `get` immediately followed by a capital letter at
Supabase call sites.

## Identifier argument labels are `id:`

Methods that took a label repeating the noun already in the method name now take `id:`.

| Before | After |
| --- | --- |
| `AuthAdminOAuth.updateClient(clientId:params:)` | `AuthAdminOAuth.updateClient(id:params:)` |
| `AuthAdminOAuth.deleteClient(clientId:)` | `AuthAdminOAuth.deleteClient(id:)` |
| `AuthAdminOAuth.regenerateClientSecret(clientId:)` | `AuthAdminOAuth.regenerateClientSecret(id:)` |
| `AuthOAuthServer.approveAuthorization(authorizationId:)` | `AuthOAuthServer.approveAuthorization(id:)` |
| `AuthOAuthServer.denyAuthorization(authorizationId:)` | `AuthOAuthServer.denyAuthorization(id:)` |
| `AuthOAuthServer.revokeGrant(clientId:)` | `AuthOAuthServer.revokeGrant(id:)` |
| `AuthAdmin.listPasskeys(userId:)` | `AuthAdmin.listPasskeys(forUser:)` |
| `AuthAdmin.deletePasskey(userId:passkeyId:)` | `AuthAdmin.deletePasskey(id:forUser:)` |

```swift
// Before
try await supabase.auth.admin.oauth.deleteClient(clientId: client.clientId)
try await supabase.auth.admin.deletePasskey(userId: user.id, passkeyId: passkey.id)

// After
try await supabase.auth.admin.oauth.deleteClient(id: client.clientId)
try await supabase.auth.admin.deletePasskey(id: passkey.id, forUser: user.id)
```

`deletePasskey` also swapped its parameter order, so the passkey comes first — the thing being
deleted, with the user as context. The `OAuthClient.clientId` *property* is unchanged; only the
argument labels moved.

These are all compile errors.

## Boolean properties read as assertions

| Before | After |
| --- | --- |
| `FileOptions.upsert` | `FileOptions.shouldUpsert` |
| `CreateSignedUploadURLOptions.upsert` | `CreateSignedUploadURLOptions.shouldUpsert` |
| `SupabaseClientOptions.StorageOptions.useNewHostname` | `usesNewHostname` |
| `AuthClient.Configuration.autoRefreshToken` | `automaticallyRefreshesToken` |
| `AuthClient.Configuration.defaultAutoRefreshToken` | `defaultAutomaticallyRefreshesToken` |
| `SupabaseClientOptions.AuthOptions.autoRefreshToken` | `automaticallyRefreshesToken` |
| `GetClaimsOptions.allowExpired` | `allowsExpired` |
| `AdminUserAttributes.emailConfirm` | `AdminUserAttributes.confirmsEmail` |
| `AdminUserAttributes.phoneConfirm` | `AdminUserAttributes.confirmsPhone` |

```swift
// Before
try await supabase.storage.from("avatars").upload(
  "me.png", data: data, options: FileOptions(upsert: true)
)
let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(auth: .init(autoRefreshToken: false))
)

// After
try await supabase.storage.from("avatars").upload(
  "me.png", data: data, options: FileOptions(shouldUpsert: true)
)
let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: .init(auth: .init(automaticallyRefreshesToken: false))
)
```

These are all compile errors. The wire formats are untouched: `FileOptions.shouldUpsert` still
sends the `x-upsert` header, and `AdminUserAttributes.confirmsEmail` still encodes to
`email_confirm`.

`head:` on `select` and `rpc` deliberately keeps its name — it names the HTTP method the request
switches to, rather than asserting a state.

## `RealtimeClientOptions.vsn` is now `protocolVersion`

`vsn` is the query parameter Realtime's server reads; it was never a good name for the Swift
property.

```swift
// Before
let client = SupabaseClient(
  supabaseURL: url, supabaseKey: key,
  options: .init(realtime: RealtimeClientOptions(vsn: .v2))
)

// After
let client = SupabaseClient(
  supabaseURL: url, supabaseKey: key,
  options: .init(realtime: RealtimeClientOptions(protocolVersion: .v2))
)
```

This is a compile error. The socket URL still carries `vsn=2.0.0` — only the Swift spelling moved.

## `User.aud` is now `User.audience`

`User.aud` is `User.audience`, and the `aud` field on `ListUsersPaginatedResponse` and
`ListOAuthClientsPaginatedResponse` is `audience` on both.

```swift
// Before
if user.aud == "authenticated" { ... }

// After
if user.audience == "authenticated" { ... }
```

`User` gained an explicit `CodingKeys` (mapping `audience` back to `"aud"`) so the wire format is
unchanged — a `User` encoded by v2 still decodes in v3, and vice versa.

`JWTClaims.aud` deliberately keeps its name. That type is a direct RFC 7519 claims bag whose
fields are all the registered abbreviations — `iss`, `sub`, `exp`, `iat`, `nbf`, `jti` — and
spelling out one of them would be less consistent, not more.

This is a compile error where you read the property. If you encode a `User` to your own storage
under a hand-written coder, check that it still expects `aud`.

## `SortBy.order` is now `SortOrder`, not `String`

`SortBy.order` stored the raw `"asc"`/`"desc"` string even though the initializer already took a
type-safe `SortOrder`, throwing that type safety away one property read later.

```swift
// Before
var sortBy = SortBy(column: "name", order: .ascending)
let raw: String? = sortBy.order   // "asc"

// After
var sortBy = SortBy(column: "name", order: .ascending)
let order: SortOrder? = sortBy.order   // .ascending
```

Reading or declaring `.order` as a `String` is a compile error. Assigning or comparing it against
the raw string literals (`sortBy.order = "asc"`, `sortBy.order == "asc"`) keeps compiling unchanged
— `SortOrder` is `ExpressibleByStringLiteral` — but now produces a `SortOrder`, not a `String`, so
comparing against any value other than `"asc"`/`"desc"` no longer type-checks. The wire format is
unchanged either way: `SortOrder` still encodes to `"asc"`/`"desc"`.

## Storage's `upload`/`update`/`uploadToSignedURL` label their file path

Every other `StorageFileApi` method that takes a file path labels it `path:` — `download(path:)`,
`info(path:)`, `exists(path:)`, `createSignedURL(path:...)`. `upload`, `update`, and
`uploadToSignedURL` were the exception, taking it positionally.

```swift
// Before
try await storage.from("avatars").upload("user123.png", data: imageData)
try await storage.from("avatars").update("user123.png", data: imageData)
try await storage.from("avatars").uploadToSignedURL("user123.png", token: token, data: imageData)

// After
try await storage.from("avatars").upload(path: "user123.png", data: imageData)
try await storage.from("avatars").update(path: "user123.png", data: imageData)
try await storage.from("avatars").uploadToSignedURL(path: "user123.png", token: token, data: imageData)
```

This is a compile error. All six overloads move together (`data:` and `fileURL:` variants of each).

## `@Table`'s `schema:` takes a type, not a string

A relation names its schema with a type, so a relation queried through the wrong schema is a
compile error rather than a request the database rejects.

```swift
// Before
@Table("secrets", schema: "private")
struct Secret { ... }

// After
enum PrivateSchema: PostgrestSchema {
  static let name = "private"
}

@Table("secrets", schema: PrivateSchema.self)
struct Secret { ... }
```

`@Table("todos")` is unchanged: a relation that names no schema belongs to `PublicSchema`.

The type is what the new scope checks against. `SupabaseClient` and `PostgrestClient` both have it:

```swift
try await supabase.schema(PrivateSchema.self).from(Secret.self).select().execute()  // valid
try await supabase.schema(PrivateSchema.self).from(Todo.self).select().execute()    // compile error
```

`schema("private")` still exists and still returns a `PostgrestClient`. Reach for it when the
schema is not known at compile time.

Three things the compiler will not catch:

- `from(Secret.self)` now sends `Accept-Profile: private`, taken from the relation. It previously
  ignored the relation's schema. A schema already set on the client wins over the relation, and
  that includes `"public"`: with `SupabaseClientOptions(db: .init(schema: "public"))`,
  `supabase.from(Secret.self)` queries `public`.
- The typed `schema(_:)` traps on a client that already has a schema, so
  `client.schema("other").schema(PrivateSchema.self)` is a programmer error, as is
  `supabase.schema(PrivateSchema.self)` when `db.schema` is set.
- `PostgrestRelation` no longer requires `static var schema: String`; the schema comes from the
  `Schema` type. A hand-written conformance that declares `static let schema = "private"` still
  compiles, but the string is no longer read and the relation is queried in `public`. Replace it
  with `typealias Schema = PrivateSchema`.

## `AuthClient` is now a `final class`, not an `actor`

`AuthClient` is declared `public final class AuthClient: Sendable` instead of
`public actor AuthClient`.

Almost every member was already `nonisolated`, so the actor protected no state. Its one side effect
was a process-global registry that those `nonisolated` members used to reach the client's
dependencies, and that registry trapped with `fatalError` as soon as an `AuthAdmin`, `AuthMFA`, or
`AuthOAuthServer` value outlived the `AuthClient` it came from. Dependencies now live on the
instance. `AuthMFA` and `AuthOAuthServer` retain their client, and `AuthAdmin` carries its own
transport, so those values keep working for as long as you hold them.

Ordinary use is source-compatible. Every member that talks to the server is still `async`, and the
members that were `nonisolated` keep working without `await`. Two synchronous methods that used to
need `await` because of actor isolation no longer do: `startAutoRefresh()` and `stopAutoRefresh()`.
Calling them with `await` still compiles but produces a "no 'async' operations occur within
'await' expression" warning; drop the `await`.

It is a compile error only where `AuthClient` was used *as an actor*: an `isolated AuthClient`
parameter, passing it where `any Actor` is expected, or calling `assumeIsolated` on it.

```swift
// Before
func inspect(_ auth: isolated AuthClient) {
  print(auth.currentUser?.email ?? "signed out")
}

// After
func inspect(_ auth: AuthClient) {
  print(auth.currentUser?.email ?? "signed out")
}
```

Search your code for `isolated AuthClient`, `assumeIsolated` on an `AuthClient` value, and
`await` in front of `startAutoRefresh()` / `stopAutoRefresh()`.

## Storage uploads send the raw file body instead of a `multipart/form-data` form

`StorageFileApi.upload`, `update`, and `uploadToSignedURL` put the file bytes directly in the
request body. The form fields the multipart body used to carry travel as headers instead:

| Multipart form field | Header |
| --- | --- |
| `cacheControl` | `Cache-Control: max-age=<seconds>` (already sent before) |
| file part `Content-Type` | `Content-Type: <contentType, or inferred from the extension>` |
| `metadata` | `x-metadata: <base64 of the JSON object>` |

This is the shape supabase-js sends for `ArrayBuffer` and stream uploads, and storage-api has
accepted it for as long as it has accepted the form. The multipart encoder buffered the whole
file three times over (measured at +610 MB for a 200 MiB upload); the raw body adds nothing on top
of the caller's data, and `upload(path:fileURL:)` now streams from disk without reading the file
into memory. The internal `MultipartFormData` type is gone.

```swift
// Before and after — the call is unchanged
try await storage.from("avatars").upload(
  path: "user123.png",
  data: imageData,
  options: FileOptions(cacheControl: "7200", metadata: ["source": "camera"])
)
```

This compiles unchanged. It is a silent wire change: anything that inspects the outgoing request
sees a different body and `Content-Type`. Search your code for a `ClientMiddleware`, a
`ClientTransport`, a proxy rule, or a test fixture that matches on `multipart/form-data`, a
`boundary=` parameter, or a `Content-Disposition: form-data` part, and read the file from the body
and the metadata from `x-metadata` instead.

A `Content-Type` passed through `FileOptions.headers` now wins over the inferred one, where before
it silently replaced the multipart header and broke the request.

## MFA factor IDs are now `UUID`, not `String`

Every place in the Auth module that holds an MFA factor's identifier now uses `UUID` instead of
`String`: `Factor.id`, `AuthMFAEnrollResponse.id`, `AuthMFAUnenrollResponse.id`,
`MFAChallengeParams.factorId`, `MFAVerifyParams.factorId`, `MFAUnenrollParams.factorId`,
`MFAChallengeAndVerifyParams.factorId`, `AuthMFA.verifyWebAuthnFactor(factorId:presentationAnchor:)`,
and the new `AuthAdminMFA.deleteFactor(id:forUser:)`.

GoTrue always generates factor IDs as UUIDv4 (`internal/models/factor.go`); keeping them as
`String` on the client meant every one of these APIs accepted values GoTrue could never actually
return.

```swift
// Before
let factors = try await supabase.auth.mfa.listFactors()
try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factors.totp[0].id))

// After — factor.id is already a UUID, nothing to convert
let factors = try await supabase.auth.mfa.listFactors()
try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factors.totp[0].id))
```

This is a compile error anywhere a factor ID was treated as a `String` directly — stored in a
`String` property, passed to an API expecting `String`, or interpolated and then passed back
(`"\(factor.id)"`). The common pattern of reading `.id` off a `Factor`/`AuthMFAEnrollResponse` and
passing it straight into another MFA call keeps compiling unchanged, since both sides are now
`UUID`. If you display or log a factor ID, use `.uuidString` to get the string form back.

## Seven more enum-like values are now structs, not enums

| Type | Module |
| --- | --- |
| `AuthChangeEvent` | Auth |
| `RealtimeClientStatus` | Realtime |
| `RealtimeChannelStatus` | Realtime |
| `HeartbeatStatus` | Realtime |
| `PushStatus` | Realtime |
| `LogLevel` | Realtime |
| `RealtimeMessageV2.EventType` | Realtime |

Each is a `RawRepresentable` struct with `static let` members instead of an `enum`, following the
same pattern as `FactorStatus` and the other conversions above.

In a source package every `enum` is frozen: adding a case is a compile error in every app with an
exhaustive `switch` over it. supabase-js has added auth events over time (`MFA_CHALLENGE_VERIFIED`
was the latest) and each one forced a major bump here. The Realtime server owns the push reply
statuses and the channel event names, so a value it adds used to come back as `nil` or, for a push
reply, as `.ok`. The client and channel statuses are client-side,
but a reconnecting or errored state is a plausible addition that should not need a major release.
The policy is written up in `Sources/Supabase/Supabase.docc/EnumsAndOpenSets.md`.

```swift
// Before
switch status {
case .disconnected: showOffline()
case .connecting: showSpinner()
case .connected: showOnline()
}

// After
switch status {
case .disconnected: showOffline()
case .connecting: showSpinner()
case .connected: showOnline()
default: showOffline()  // a status added in a later SDK release
}
```

This is a compile error only if you have an exhaustive `switch` over one of these types — add a
`default:` case. Equality (`event == .signedIn`), `contains` checks, and construction from a
literal (`let level: LogLevel = "info"`) work unchanged.

`init(rawValue:)` is no longer failable — it always succeeds, even for an unrecognized value.
`if let event = AuthChangeEvent(rawValue: someString) { ... }` no longer compiles ("Initializer
for conditional binding must have Optional type") — replace it with
`let event = AuthChangeEvent(rawValue: someString)` directly. If your code used
`X(rawValue:) != nil` to validate a string, that check still compiles but is now always `true` —
this is a silent behavior change, not a compile error, so search for that pattern and remove or
replace it.

String interpolation changes silently. `"\(AuthChangeEvent.signedIn)"` used to print the case
name (`signedIn`); it now prints the struct's default description
(`AuthChangeEvent(rawValue: "SIGNED_IN")`). Use `.rawValue` explicitly to get the bare string
back. `RealtimeClientStatus` keeps its `CustomStringConvertible` conformance but now prints the
raw value (`connected`) instead of the capitalized case name (`Connected`).

Two smaller behavior changes ride along:

- `PushStatus`: a reply status this SDK had no case for used to be reported as `.ok`. It is now
  reported with its raw value intact, so `status == .ok` is `false` for it. If you treat anything
  other than `.error` and `.timeout` as success, compare against those two instead.
- `RealtimeMessageV2.eventType` is new and non-optional. The internal event classification used
  to return `nil` for an event name the SDK did not handle; it now returns an `EventType` whose
  `rawValue` is the event name.

## MFA challenge IDs are now `UUID` instead of `String`

`AuthMFAChallengeResponse.id` and `MFAVerifyParams.challengeId` are `UUID` instead of `String`.
Both `MFAVerifyParams` initializers take `challengeId: UUID`.

The Auth server stores a challenge ID in a `uuid` column, returns it as a UUID, and rejects a
`challenge_id` in `POST /factors/{id}/verify` that does not parse as one. A `String` let callers
build a request the server could only refuse.

```swift
// Before
let challenge = try await supabase.auth.mfa.challenge(params: .init(factorId: factorId))
let challengeId: String = challenge.id
try await supabase.auth.mfa.verify(
  params: .init(factorId: factorId, challengeId: challengeId, code: code)
)

// After
let challenge = try await supabase.auth.mfa.challenge(params: .init(factorId: factorId))
let challengeId: UUID = challenge.id
try await supabase.auth.mfa.verify(
  params: .init(factorId: factorId, challengeId: challengeId, code: code)
)
```

Code that passes `challenge.id` straight into `verify` compiles unchanged. Code that stores the
ID as a `String`, or builds `MFAVerifyParams` from a string, gets a compile error. Convert with
`challenge.id.uuidString` and `UUID(uuidString:)`. A `UUID` prints in uppercase, so
`"\(challenge.id)"` changes case if you compare it with a lowercase ID.

`challengeAndVerify(params:)` is unchanged. Passkey challenge IDs
(`PasskeyRegistrationOptions.challengeId`, `PasskeyAuthenticationOptions.challengeId`) stay
`String`, because the passkey endpoints type `challenge_id` as a string.

## `PostgrestTransformBuilder.order(_:ascending:nullsFirst:)` no longer defaults to `NULLS LAST`

`nullsFirst` is now `Bool?`, defaulting to `nil` instead of `false`. When it is `nil`, the request
sends no null placement at all, instead of always appending `.nullslast`.

`nullsFirst: false` always rendered `.nullslast`, even for a descending sort, where Postgres's own
default is `NULLS FIRST`. So `.order("due_at", ascending: false)` silently reversed the database's
null placement instead of leaving it alone — and diverged from supabase-js, which only sends a
placement when the caller asks for one.

```swift
// Before — sent order=due_at.desc.nullslast, forcing NULLs to the end
try await client.from("todos").select().order("due_at", ascending: false).execute()

// After — sends order=due_at.desc, so Postgres applies NULLS FIRST on a descending sort
try await client.from("todos").select().order("due_at", ascending: false).execute()
```

This does not change compilation — `nullsFirst: Bool? = nil` still accepts a literal `true` or
`false` at any call site. It is a silent behavior change: a query that relied on the implicit
`NULLS LAST` on a descending sort over a nullable column now returns rows in a different order.
Search your codebase for `.order(` calls that omit `nullsFirst` on a descending sort, and pass
`nullsFirst: false` explicitly to keep the old placement.

The typed `order { }` API added alongside this (SDK-1624) already worked this way and is
unaffected.

## `insert` and `upsert` return `PostgrestTransformBuilder`; filters no longer compile after them

`PostgrestQueryBuilder.insert(_:returning:count:defaultToNull:encoder:)` and
`upsert(_:onConflict:returning:count:ignoreDuplicates:defaultToNull:encoder:)` return
`PostgrestTransformBuilder` instead of `PostgrestFilterBuilder`. `update` and `delete` still return
`PostgrestFilterBuilder`.

An insert has no existing rows to match, and PostgREST ignores filters on a `POST`. A filter
chained after `insert` or `upsert` compiled and ran, but did nothing. This matches the same fix in
supabase-flutter.

```swift
// Before: compiles, and the server ignores the eq
try await client
  .from("todos")
  .insert(["task": "Buy milk"])
  .eq("id", value: 1)
  .execute()

// After: remove the filter
try await client
  .from("todos")
  .insert(["task": "Buy milk"])
  .execute()
```

This is a compile error at every filter (`eq`, `match`, `or`, `filter`, ...) chained after
`insert` or `upsert`. Delete the filter: it never had an effect. Every transform still compiles
after `insert` and `upsert`, so `select`, `order`, `limit`, `range`, `single`, `maybeSingle`, `csv`
and the others are unchanged. Code that stores the result in a variable or parameter typed
`PostgrestFilterBuilder` also gets a compile error. Change the type to `PostgrestTransformBuilder`,
or to `any PostgrestExecutableBuilder` if the same variable also holds an `update` or `delete`.

## The typed PostgREST wrappers drop the `Typed` prefix

The types behind `client.from(Todo.self)` are renamed. Nothing else about them changes in this step.

| Before | After |
| --- | --- |
| `PostgrestTypedSource` | `PostgrestSource` |
| `PostgrestTypedQuery` | `PostgrestQuery` |
| `PostgrestTypedMutation` | `PostgrestMutation` |

The typed API is marked alpha, and these are the names the PostgREST v3 design uses. The prefix
only existed to keep clear of the string builders, whose names are `PostgrestQueryBuilder`,
`PostgrestFilterBuilder` and `PostgrestTransformBuilder`, so the shorter names were free. Renaming
now, before the typed API is stable, costs less than teaching early adopters a name we plan to drop.

```swift
// Before
let query: PostgrestTypedQuery<Todo, [Todo], PostgrestFilterPhase> = client.from(Todo.self).select()

// After
let query: PostgrestQuery<Todo, [Todo], PostgrestFilterPhase> = client.from(Todo.self).select()
```

This is a compile error only where your code spells a type name. A chain that starts at
`from(Todo.self)` and never names its type compiles unchanged. Search for `PostgrestTyped`.

## `PostgrestQuery`, `PostgrestMutation` and `PostgrestSource` no longer wrap a builder

The typed wrappers now hold a `PostgrestRequest` value instead of a `PostgrestRequestBuilder`.
Four things change for callers:

| Before | After |
| --- | --- |
| `PostgrestQuery<R, Output, Phase>` | `PostgrestQuery<R, Output>` |
| `query.builder`, `mutation.builder` | removed |
| `PostgrestQuery(builder:)`, `PostgrestMutation(builder:)` | removed |
| `PostgrestFilterableRequest.builder` and `.Phase` | `PostgrestFilterableRequest.request` |

The `Phase` parameter is gone because the modifiers no longer depend on order. `where`, `order`,
`limit` and `range` all return the same type, so `.order { … }.where { … }` now compiles. Before,
`order` moved the query into a phase without `where`.

`builder` was the escape hatch back to the string API. A query no longer holds a builder, so there
is nothing to hand back, and keeping a conversion only to delete it later was not worth it. The
typed API is alpha, which is what allows dropping it outright.

```swift
// Before
let query: PostgrestQuery<Todo, [Todo], PostgrestTransformPhase> = client.from(Todo.self)
  .select()
  .order { $0.id.asc() }
let rows: [Todo] = try await query.builder.setHeader(name: "X-Trace", value: id).execute().value

// After
let query: PostgrestQuery<Todo, [Todo]> = client.from(Todo.self)
  .select()
  .order { $0.id.asc() }
let rows = try await query.execute().value
```

This is a compile error wherever your code names the `Phase` parameter or touches `builder`. A
chain that starts at `from(Todo.self)` and never names its type compiles unchanged. Search for
`.builder` and for `PostgrestFilterPhase` and `PostgrestTransformPhase` next to `PostgrestQuery`.

There is no escape hatch on the typed path for per-request headers, `retry(enabled:)` or
`timeout(_:)` yet. Set headers and the timeout on `PostgrestClient.Configuration`, or use the
string API (`client.from("todos")`) for a request that needs them.

The same change adds `single()`, `maybeSingle()`, `stripNulls()`, `csv()`, `geojson()` and
`explain(…)` to `PostgrestQuery`. `single()` decodes `Element` instead of `[Element]`, and
`maybeSingle()` decodes `Element?`. It sends the usual array request and checks the count on
the client: no row is `nil`, and more than one row throws a `PostgrestError` of kind `.decoding`.
The string builder's `maybeSingle()` instead asks for a single object and maps PostgREST's
`PGRST116` to `nil`. `csv()`, `geojson()` and
`explain(…)` return a `PostgrestRawQuery`, whose `execute()` returns the body as a `String`. That
type has no `stripNulls()`, so `.csv().stripNulls()` does not compile, where the string builder
throws at `execute()`.
## `update`/`upsert`/`delete` no longer default to returning rows

`PostgrestRequestBuilder.update(_:returning:count:encoder:)`,
`upsert(_:onConflict:returning:count:ignoreDuplicates:defaultToNull:encoder:)`, and
`delete(returning:count:)` now default `returning` to `nil` and omit `Prefer: return=` entirely
when the caller doesn't pass it, matching `insert(_:returning:count:defaultToNull:encoder:)` and
PostgREST's own default of `return=minimal`.

Previously these three defaulted `returning` to `.representation` and always sent
`Prefer: return=representation`, so a bare `update`/`upsert`/`delete` call — one that never chained
`.select()` — silently paid for a response body it discarded. `insert` never had this problem, and
js and Flutter omit the header by default on all four methods, so Swift's defaults were
inconsistent with both itself and the rest of the SDK family.

```swift
// Before — rows came back even without .select()
let updated: [Todo] = try await client
  .from("todos")
  .update(["done": true])
  .eq("id", value: 1)
  .execute()
  .value

// After — chain .select() to get rows back, as insert already required
let updated: [Todo] = try await client
  .from("todos")
  .update(["done": true])
  .eq("id", value: 1)
  .select()
  .execute()
  .value
```

This does not break the build — `returning` was already optional-looking at call sites that never
passed it — but it is a silent behavior change: a bare `update`/`upsert`/`delete` call that decodes
`.value` without chaining `.select()` now decodes an empty response instead of the modified rows.
Search your codebase for `.update(`, `.upsert(`, and `.delete(` calls that read `.value` or
`.execute().value` without a `.select()` in the chain, and either add `.select()` or pass
`returning: .representation` explicitly to keep the old behavior. The typed query API
(`from(_:)`) already defaulted to `.minimal` and is unaffected.

## SDK `async` functions run on the caller's executor (`NonisolatedNonsendingByDefault`)

Every SDK target now builds with Swift 6.2's `NonisolatedNonsendingByDefault` (SE-0461). A
nonisolated `async` method such as `PostgrestTypedQuery.execute()`,
`FunctionsClient.invoke(_:options:decoder:)` or `AuthClient.session` now runs on the executor of
its caller instead of hopping to the global concurrent executor. Called from `@MainActor` code,
it stays on the main actor between suspension points.

The SDK's own build flags decide how its `async` functions run; your app's flags do not reach SDK
code. Moving a function to caller isolation changes its ABI, so the v3 major is the one moment to
do it. It also makes decoding into your own `Decodable` types sound when those conformances are
`@MainActor`-isolated, which is the default in an app that turns on
`defaultIsolation(MainActor.self)`.

### `ClientMiddleware.intercept(_:body:next:)` spells `next` as `nonisolated(nonsending)`

The `next` parameter is now
`nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws -> (HTTPResponse, HTTPBody?)`.
A middleware in a module that does **not** enable `NonisolatedNonsendingByDefault` (the default
for Swift packages) no longer conforms until it spells the same type:

```swift
// Before
func intercept(
  _ request: HTTPRequest, body: HTTPBody?,
  next: @Sendable (HTTPRequest, HTTPBody?) async throws -> (HTTPResponse, HTTPBody?)
) async throws -> (HTTPResponse, HTTPBody?)

// After
func intercept(
  _ request: HTTPRequest, body: HTTPBody?,
  next: nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws
    -> (HTTPResponse, HTTPBody?)
) async throws -> (HTTPResponse, HTTPBody?)
```

This is a compile error (`type '...' does not conform to protocol 'ClientMiddleware'`). In a
module that already enables the flag (Xcode 26's "Approachable Concurrency" turns it on), the old
spelling means the same type and keeps compiling. `ClientTransport` conformances need no change.

### Work you `await` from the main actor now stays there

This part is silent: it compiles unchanged. Decoding a large PostgREST, Functions or Storage
response into your types now happens on the actor that awaited the call. If you fetch large
result sets from `@MainActor` code and see the UI stall, move the call off the main actor:

```swift
// Before: decoding ran off the main actor implicitly
@MainActor func load() async throws {
  rows = try await client.from("todos").select().execute().value
}

// After: opt out explicitly where it matters
@concurrent func fetchTodos() async throws -> [Todo] {
  try await client.from("todos").select().execute().value
}

@MainActor func load() async throws {
  rows = try await fetchTodos()
}
```

`@concurrent` needs `Todo`'s `Decodable` conformance to be nonisolated. Search for `await` calls
into the SDK from `@MainActor` code that return large payloads.

`HTTPBody`'s iterator stays `@concurrent`, so reading a response body chunk by chunk still leaves
the caller's actor. Realtime decodes WebSocket frames in its own task, as before.
