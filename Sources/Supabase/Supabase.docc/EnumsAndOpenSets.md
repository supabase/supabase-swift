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

- The cases carry associated values, so a struct cannot express them: `AuthResponse`,
  `VerifyOTPResponse`, `OAuthAuthorizationDetailsResponse`, `AudienceClaim`, `SignedURLResult`,
  `DownloadBehavior`, `AnyAction`, `RealtimePostgresFilter`, `JSONValue`.
- The SDK has to implement each case, so a value it has no code for is meaningless:
  `AuthFlowType`, `RealtimePostgresIsValue`, `PostgrestFilterOperator`, `PostgresChangeEvent`
  (each event maps to its own `PostgresAction` type).

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
  `FactorStatus`, `PushStatus`, `LogLevel`, `RealtimeMessageV2.EventType`.
- Consumers `switch` over it and the SDK expects to add members in minor releases:
  `AuthChangeEvent`, `RealtimeClientStatus`, `RealtimeChannelStatus`, `HeartbeatStatus`.

These types conform to `RawRepresentable`, `Hashable`, `Sendable` and `ExpressibleByStringLiteral`.
The known values are `static let` members, so call sites read the same as they did with an
`enum`, but a `switch` needs a `default:` case:

```swift
switch client.status {
case .connected: showOnline()
case .connecting: showSpinner()
case .disconnected: showOffline()
default: showOffline()  // a status added in a later SDK release
}
```

Equality, `contains`, and string literals work as you would expect:

```swift
if event == .signedIn { ... }
if [.signedIn, .tokenRefreshed].contains(event) { ... }
let level: LogLevel = "debug"  // a value the SDK has no member for yet
```

`init(rawValue:)` never fails. An unrecognized value round-trips through `rawValue` instead of
failing to decode or blocking construction until an SDK upgrade. Use `rawValue` when you log or
persist one of these values; interpolating the struct directly prints its default description,
not the bare string.
