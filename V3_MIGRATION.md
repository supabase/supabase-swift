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
instead of an `enum`.

It's currently only ever sent as a request parameter, but it's `Codable` and part of the public
API surface — if GoTrue starts echoing it back in a response (e.g. once a new channel like
Telegram ships), an `enum` would fail to decode an unrecognized value instead of round-tripping it.
Converting now closes that gap ahead of time rather than after a real decode failure.

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
struct instead of an `enum`. It no longer conforms to `CaseIterable` or `Identifiable`.

New OAuth providers are added by GoTrue on an ongoing basis, and `Provider` is `Codable` and part
of the public API surface. As an `enum`, decoding a `Provider` value this SDK version didn't have
a case for would throw a `DecodingError` instead of round-tripping the provider name — converting
now closes that gap ahead of GoTrue actually returning one through a typed field.

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

It's sent to the backend, not decoded from it, but it's `Codable` and part of the public API
surface, and the set of OIDC-capable providers can grow — as an `enum`, using a provider this SDK
version didn't have a case for meant waiting on an SDK upgrade even though GoTrue might already
support it.

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
