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
