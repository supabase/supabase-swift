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

**OSLog parity.** `OSLogSupabaseLogger`'s zero-config OSLog/Console.app integration is replaced by
`OSLogHandler`, constructed explicitly and installed as the backing handler for a `Logger` (add
`import Logging` to this file):

```swift
logger: Logger(label: "myapp") { OSLogHandler(label: $0) }
```

`OSLogHandler` forwards every level by default (`logLevel` defaults to `.trace`), matching
`OSLogSupabaseLogger`'s old always-forward behavior — use Console.app's own filtering, or set
`logger.logLevel` yourself, to narrow what's emitted.

If this file also has `import OSLog` — which it will if you're wiring up `OSLogHandler` alongside
your app's own OSLog-based logging — you'll hit a `'Logger' is ambiguous for type lookup` compile
error, because both `Logging.Logger` and `os.Logger` are now in scope unqualified in that file.
Fix it by fully qualifying whichever type you mean less often, e.g. `os.Logger` for OSLog's own
type:

```swift
import Logging
import OSLog

let appLogger = os.Logger(subsystem: "myapp", category: "app")
let supabaseLogger = Logging.Logger(label: "myapp") { OSLogHandler(label: $0) }
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
