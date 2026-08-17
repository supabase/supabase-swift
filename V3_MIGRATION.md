# V3 Migration Guide

This document describes the breaking changes you need to be aware of when upgrading to v3 of the
Supabase Swift SDK, together with the steps required to migrate your code. All modules
(`Auth`, `Storage`, `Realtime`, `PostgREST`, `Functions`, `Supabase`) are covered here.

> [!NOTE]
> v3 has not been released yet. This document is updated as breaking changes land on `main`, so
> treat it as the running list rather than the final one.

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
| `AuthError.pkce(_:)` / `AuthError.PKCEFailureReason` | `AuthError.pkceGrantCodeExchange(message:error:code:)` |
| `AuthError.invalidImplicitGrantFlowURL` | `AuthError.implicitGrantRedirect(message:)` |
| `AuthError.api(_ error: APIError)` / `AuthError.APIError` | `AuthError.api(message:errorCode:underlyingData:underlyingResponse:)` |
| `UserAttributes.emailChangeToken` | *(removed, no replacement — was unused by GoTrue)* |

Also removed, with no replacement, because they no longer represent something GoTrue can throw:
`AuthError.missingExpClaim`, `AuthError.malformedJWT`, `AuthError.missingURL`,
`AuthError.invalidRedirectScheme`.

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
| `Storage.File` / `Storage.FormData` | `MultipartFormData` |

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

## `KeychainLocalStorage`'s default Keychain service is now the host app's bundle identifier

`KeychainLocalStorage()` no longer stores sessions under the fixed service
`"supabase.gotrue.swift"`. It now defaults to `Bundle.main.bundleIdentifier`, falling back to the
old constant only when there is no bundle identifier to read (command-line tools, some test
bundles).

The fixed string put every app that embeds the SDK in the same Keychain namespace. On
iOS/iPadOS/tvOS/watchOS/visionOS this was not a cross-app collision risk, since items are
implicitly scoped to the app's own default access group
(`$(AppIdentifierPrefix)$(CFBundleIdentifier)`), so unrelated apps could not read or overwrite each
other's session there. On macOS's file-based login Keychain, and for any apps deliberately sharing
an access group on any platform, the shared service name was a real collision risk: two such apps
could read and overwrite each other's session under that one service name. Either way, sharing a
single hardcoded service name is poor namespacing hygiene. Scoping the service to the bundle
identifier gives each app its own Keychain location by default.

Existing sessions are not lost. On the first `retrieve` after upgrading, `KeychainLocalStorage`
probes the old `"supabase.gotrue.swift"` location, moves whatever it finds to the new
per-app location, and returns it — so users stay signed in. This is a behavior change, not a
compile error: nothing in the type signature changed, but the on-disk Keychain location did. If
you rely on the exact service name (for example, to inspect the Keychain from another tool, or
because several of your own apps intentionally shared the old namespace), pass it explicitly to
keep the pre-v3 location:

```swift
// Before (implicit, shared "supabase.gotrue.swift" service)
let storage = KeychainLocalStorage()

// After: keeps the pre-v3 location, no migration performed
let storage = KeychainLocalStorage(service: "supabase.gotrue.swift")
```

Note that passing `service:` explicitly — whether the old constant or a new value of your own —
selects the second, non-migrating initializer: `init(service:accessGroup:useDataProtectionKeychain:)`.
Only the parameterless-service initializer, `init(accessGroup:useDataProtectionKeychain:)`, probes
the legacy location.

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
service name — the service-namespacing change above does not affect it, since the ACL that
triggers the prompt is governed by code-signing identity, not by `kSecAttrService` (see [Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)).
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
