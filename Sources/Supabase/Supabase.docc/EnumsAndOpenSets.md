# Enums and Open Sets

How the SDK decides between an `enum` and a struct with static members, and how to `switch` over
each.

## Overview

Swift treats every `enum` in a source package as frozen. An exhaustive `switch` compiles without
a `default:` case, and adding a case later breaks every such `switch` in every app that depends
on the package. The SDK keeps that guarantee for sets that cannot grow, and avoids it for sets
that can.

### Closed sets are enums

A value stays an `enum` when the set of cases is fixed by design:

- The cases carry associated values, so a struct cannot express them: `AuthStatus`, `SignUpResult`,
  `RedirectResult`, `VerifyOTPResult`, `SSOTarget`, `OAuthAuthorizationDetailsResult`, `SignedURLResult`,
  `DownloadBehavior`, `BroadcastPayload`, `RealtimePostgresFilter`, `JSONValue`,
  `RealtimeClientStatus`, `RealtimeChannelStatus`. The two status enums are not `Equatable`,
  because their cases carry errors: match a case, or use `isConnected`, `isSubscribed` and
  `error`.
- The client produces the value and never reads it from the server, so only an SDK release can
  add a case: `RealtimeChannelEvent`, `HeartbeatEvent`.
- The SDK has to implement each case, so a value it has no code for is meaningless:
  `RealtimePostgresIsValue`, `_PostgrestFilterOperator`, `_PostgrestAggregateFunction`,
  `PostgresChangeEvent` (the SDK sends each event in the join request), `SignOutScope`,
  `AuthClient.AutoRefreshPolicy`, `KeychainStorage.Accessibility`.

Switch over these exhaustively. Adding a case to one of them is a breaking change and only ships
in a major release, so the compiler tells you exactly where to look when you upgrade.

```swift
switch result {
case .success(let value): ...
case .failure(let error): ...
}
```

### Open sets are structs with static members

A value is a `RawRepresentable` struct when the set can grow without a major release:

- The server defines it, so a new value can appear before the SDK has a name for it: `Provider`,
  `FactorStatus`, `RealtimeServerLogLevel`, `PostgresChange.Kind`,
  `WebSocketCloseCode`, and the error code of every module: `AuthError.Code`,
  `PostgrestError.Code`, `StorageError.Code`, `FunctionsError.Code`, `RealtimeError.Code`.
- The SDK expects to add members in minor releases: `AuthEvent`, and the error kind of every
  module (`AuthError.Kind`, `StorageError.Kind`, and so on).

These types conform to `RawRepresentable`, `Hashable`, `Sendable` and `ExpressibleByStringLiteral`
(`ExpressibleByIntegerLiteral` for `WebSocketCloseCode`). Each has a `let rawValue`,
`init(rawValue:)` and the literal initializer, and no other initializer. The known values are
`static let` members, so call sites read the same as they did with an
`enum`, but a `switch` needs a `default:` case:

```swift
switch event {
case .signedIn: showHome()
case .signedOut: showSignIn()
default: break  // includes events added in a later SDK release
}
```

Equality, `contains`, and string literals work as you would expect:

```swift
if event == .signedIn { ... }
if [.signedIn, .tokenRefreshed].contains(event) { ... }
let level: RealtimeServerLogLevel = "debug"  // a value the SDK has no member for yet
```

Error kinds and error codes also match an error directly in a `catch` clause:

```swift
do {
  try await supabase.storage.from("avatars").download(path: "a.png")
} catch StorageError.Code.noSuchKey {
  showPlaceholder()
} catch StorageError.Kind.transport {
  showOfflineBanner()
}
```

`init(rawValue:)` never fails. An unrecognized value round-trips through `rawValue` instead of
failing to decode or blocking construction until an SDK upgrade. Use `rawValue` when you log or
persist one of these values; interpolating the struct directly prints its default description,
not the bare string.
