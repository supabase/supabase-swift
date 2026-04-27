# Realtime v3 — Phase 8 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `@RealtimeTable` macro, wire `_Realtime` into `SupabaseClient`, write integration tests, and produce the migration guide.

**Architecture:** The macro lives in a separate `Packages/_RealtimeTableMacros/` Swift package (requires `swift-syntax`). The macro declaration (`@attached(extension)`) lives in `_Realtime` and references the macro plugin. `SupabaseClient` gains a `realtime: Realtime` computed property that reads from `supabaseURL` + `supabaseKey`. Integration tests target a local Supabase instance via `supabase start`.

**Prerequisite:** Phases 1–7 complete and committed.

---

## Task 1: `@RealtimeTable` macro package

**Files:**
- Create: `Packages/_RealtimeTableMacros/Package.swift`
- Create: `Packages/_RealtimeTableMacros/Sources/_RealtimeTableMacros/RealtimeTableMacro.swift`
- Create: `Packages/_RealtimeTableMacros/Tests/_RealtimeTableMacrosTests/RealtimeTableMacroTests.swift`
- Modify: `Packages/_Realtime/Package.swift` (add macro dependency + plugin)
- Create: `Packages/_Realtime/Sources/_Realtime/Macros/RealtimeTable+Macro.swift`

- [ ] **Step 1: Create macro package scaffold**

```bash
mkdir -p Packages/_RealtimeTableMacros/Sources/_RealtimeTableMacros
mkdir -p Packages/_RealtimeTableMacros/Tests/_RealtimeTableMacrosTests
```

- [ ] **Step 2: Create `Packages/_RealtimeTableMacros/Package.swift`**

```swift
// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "_RealtimeTableMacros",
  platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
  products: [
    .library(name: "_RealtimeTableMacros", targets: ["_RealtimeTableMacros"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
  ],
  targets: [
    .macro(
      name: "_RealtimeTableMacroPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "_RealtimeTableMacros",
      dependencies: [
        .target(name: "_RealtimeTableMacroPlugin"),
      ]
    ),
    .testTarget(
      name: "_RealtimeTableMacrosTests",
      dependencies: [
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        "_RealtimeTableMacros",
        "_RealtimeTableMacroPlugin",
      ]
    ),
  ]
)
```

- [ ] **Step 3: Write macro expansion test (TDD)**

Create `Tests/_RealtimeTableMacrosTests/RealtimeTableMacroTests.swift`:

```swift
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import _RealtimeTableMacroPlugin

final class RealtimeTableMacroTests: XCTestCase {
  func testBasicExpansion() {
    assertMacroExpansion(
      """
      @RealtimeTable(schema: "public", table: "messages")
      struct Message: Codable, Sendable {
        var id: UUID
        var roomId: UUID
        var text: String
      }
      """,
      expandedSource: """
      struct Message: Codable, Sendable {
        var id: UUID
        var roomId: UUID
        var text: String
      }

      extension Message: RealtimeTable {
        static let schema: String = "public"
        static let tableName: String = "messages"
        static func columnName<V>(for keyPath: KeyPath<Message, V>) -> String {
          switch keyPath {
          case \\Message.id: return "id"
          case \\Message.roomId: return "room_id"
          case \\Message.text: return "text"
          default: fatalError("Unknown keypath for RealtimeTable \\(keyPath)")
          }
        }
      }
      """,
      macros: ["RealtimeTable": RealtimeTableMacro.self]
    )
  }

  func testCustomCodingKeysRespected() {
    assertMacroExpansion(
      """
      @RealtimeTable(schema: "public", table: "users")
      struct User: Codable, Sendable {
        var id: UUID
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
          case id
          case createdAt = "created_at"
        }
      }
      """,
      expandedSource: """
      struct User: Codable, Sendable {
        var id: UUID
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
          case id
          case createdAt = "created_at"
        }
      }

      extension User: RealtimeTable {
        static let schema: String = "public"
        static let tableName: String = "users"
        static func columnName<V>(for keyPath: KeyPath<User, V>) -> String {
          switch keyPath {
          case \\User.id: return "id"
          case \\User.createdAt: return "created_at"
          default: fatalError("Unknown keypath for RealtimeTable \\(keyPath)")
          }
        }
      }
      """,
      macros: ["RealtimeTable": RealtimeTableMacro.self]
    )
  }
}
```

- [ ] **Step 4: Run macro test — expect compile failure**

```bash
cd Packages/_RealtimeTableMacros && swift test 2>&1 | head -10
```

- [ ] **Step 5: Create the macro implementation**

Create `Sources/_RealtimeTableMacroPlugin/RealtimeTableMacro.swift`:

```swift
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct RealtimeTableMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw MacroError(message: "@RealtimeTable can only be applied to structs")
    }

    // Extract schema and table from macro arguments
    guard let args = node.arguments?.as(LabeledExprListSyntax.self),
          args.count >= 2,
          let schemaExpr = args.first(where: { $0.label?.text == "schema" })?.expression,
          let tableExpr = args.first(where: { $0.label?.text == "table" })?.expression,
          let schema = schemaExpr.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
          let table = tableExpr.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    else {
      throw MacroError(message: "@RealtimeTable requires schema: and table: arguments")
    }

    let typeName = structDecl.name.text

    // Find all stored properties and their column names (honoring CodingKeys)
    let columnNames = extractColumnNames(from: structDecl)

    // Build the switch cases
    let cases = columnNames.map { (prop, column) in
      "case \\\\.\(typeName).\(prop): return \"\(column)\""
    }.joined(separator: "\n          ")

    let extensionSource = """
    extension \(typeName): RealtimeTable {
      static let schema: String = "\(schema)"
      static let tableName: String = "\(table)"
      static func columnName<V>(for keyPath: KeyPath<\(typeName), V>) -> String {
        switch keyPath {
        \(cases)
        default: fatalError("Unknown keypath for RealtimeTable \\(keyPath)")
        }
      }
    }
    """

    let extensionDecl = try ExtensionDeclSyntax("\(raw: extensionSource)")
    return [extensionDecl]
  }

  // Extract (propertyName → columnName) pairs, honoring CodingKeys if present
  private static func extractColumnNames(from decl: StructDeclSyntax) -> [(String, String)] {
    // Find CodingKeys enum if it exists
    var codingKeyMap: [String: String] = [:]
    for member in decl.memberBlock.members {
      if let enumDecl = member.decl.as(EnumDeclSyntax.self),
         enumDecl.name.text == "CodingKeys" {
        for enumMember in enumDecl.memberBlock.members {
          if let caseDecl = enumMember.decl.as(EnumCaseDeclSyntax.self) {
            for element in caseDecl.elements {
              let propName = element.name.text
              if let rawValue = element.rawValue?.value.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
                codingKeyMap[propName] = rawValue
              } else {
                codingKeyMap[propName] = propName
              }
            }
          }
        }
      }
    }

    var result: [(String, String)] = []
    for member in decl.memberBlock.members {
      if let varDecl = member.decl.as(VariableDeclSyntax.self),
         varDecl.bindingSpecifier.text == "var" {
        for binding in varDecl.bindings {
          if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            let column: String
            if let mapped = codingKeyMap[name] {
              column = mapped
            } else if codingKeyMap.isEmpty {
              // No CodingKeys: camelCase → snake_case
              column = camelToSnake(name)
            } else {
              column = name
            }
            result.append((name, column))
          }
        }
      }
    }
    return result
  }

  private static func camelToSnake(_ s: String) -> String {
    var result = ""
    for (i, char) in s.enumerated() {
      if char.isUppercase && i > 0 {
        result.append("_")
        result.append(char.lowercased())
      } else {
        result.append(char)
      }
    }
    return result
  }
}

struct MacroError: Error, CustomStringConvertible {
  let message: String
  var description: String { message }
}

@main struct _RealtimeTableMacroPlugin: CompilerPlugin {
  var providingMacros: [any Macro.Type] = [RealtimeTableMacro.self]
}
```

- [ ] **Step 6: Run macro tests — expect pass**

```bash
cd Packages/_RealtimeTableMacros && swift test
```

Expected: 2 tests pass.

- [ ] **Step 7: Add macro declaration to `_Realtime`**

First, add the local macro package to `Packages/_Realtime/Package.swift`:

```swift
// In dependencies:
.package(path: "../_RealtimeTableMacros"),

// In _Realtime target dependencies:
.product(name: "_RealtimeTableMacros", package: "_RealtimeTableMacros"),
```

Then create `Sources/_Realtime/Macros/RealtimeTable+Macro.swift`:

```swift
import _RealtimeTableMacros

/// Synthesizes `RealtimeTable` conformance for a struct, enabling typed `Filter<T>`.
///
/// ```swift
/// @RealtimeTable(schema: "public", table: "messages")
/// struct Message: Codable, Sendable {
///   var id: UUID
///   var roomId: UUID
///   var text: String
/// }
///
/// // Now usable with typed filters:
/// channel.changes(to: Message.self, where: .eq(\.roomId, roomId))
/// ```
///
/// Column names follow `CodingKeys` if defined; otherwise camelCase is converted to snake_case.
@attached(extension, conformances: RealtimeTable, names: named(schema), named(tableName), named(columnName))
public macro RealtimeTable(schema: String, table: String) =
  #externalMacro(module: "_RealtimeTableMacroPlugin", type: "RealtimeTableMacro")
```

- [ ] **Step 8: Build `_Realtime` with macro**

```bash
cd Packages/_Realtime && swift build
```

Expected: Build succeeded.

- [ ] **Step 9: Commit**

```bash
git add Packages/_RealtimeTableMacros Packages/_Realtime/Sources/_Realtime/Macros Packages/_Realtime/Package.swift
git commit -m "feat(_Realtime): Phase 8a — @RealtimeTable macro synthesis"
```

---

## Task 2: `SupabaseClient` integration

**Files:**
- Modify: `Sources/Supabase/SupabaseClient.swift`
- Create: `Sources/Supabase/SupabaseClient+RealtimeV3.swift`
- Modify: `Package.swift` (root)

- [ ] **Step 1: Add `_Realtime` to the `Supabase` target in root `Package.swift`**

In the `Supabase` target's `dependencies` array, add:
```swift
.product(name: "_Realtime", package: "_Realtime"),
```

- [ ] **Step 2: Create `Sources/Supabase/SupabaseClient+RealtimeV3.swift`**

```swift
import _Realtime
import Foundation

extension SupabaseClient {
  /// Realtime v3 client. Lazily created; shares the supabase URL and API key.
  ///
  /// The v3 client uses `_Realtime` — the new idiomatic Swift API targeting iOS 17+.
  /// For iOS 13 support, use `realtimeV2` instead.
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
  public var realtimeV3: Realtime {
    if let existing = _realtimeV3 { return existing }
    var config = _Realtime.Configuration()
    if let logger = options.global.logger {
      config.logger = BridgedLogger(wrapped: logger)
    }
    let headers = options.global.headers.reduce(into: [String: String]()) { dict, pair in
      dict[pair.name.rawValue] = pair.value
    }
    config.headers = headers
    let client = Realtime(
      url: realtimeURL,
      apiKey: .dynamic { [weak self] in
        guard let self else { return "" }
        return try await self.auth.session.accessToken
      },
      configuration: config
    )
    _realtimeV3 = client
    return client
  }

  private var _realtimeV3: Realtime? {
    get { objc_getAssociatedObject(self, &AssociatedKeys.realtimeV3) as? Realtime }
    set { objc_setAssociatedObject(self, &AssociatedKeys.realtimeV3, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
  }

  private var realtimeURL: URL {
    var comps = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)!
    comps.path = "/realtime/v1"
    comps.scheme = comps.scheme == "https" ? "wss" : "ws"
    return comps.url!
  }

  private enum AssociatedKeys {
    static var realtimeV3 = "realtimeV3"
  }
}

// Bridge the existing SupabaseLogger to RealtimeLogger
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct BridgedLogger: _Realtime.RealtimeLogger {
  let wrapped: any SupabaseLogger

  func log(_ event: _Realtime.LogEvent) {
    wrapped.log(
      message: event.message,
      level: {
        switch event.level {
        case .debug: return .debug
        case .info: return .verbose
        case .warn: return .warning
        case .error: return .error
        }
      }()
    )
  }
}
```

- [ ] **Step 3: Build root package**

```bash
swift build -target Supabase
```

Expected: Build succeeded.

- [ ] **Step 4: Commit**

```bash
git add Sources/Supabase/SupabaseClient+RealtimeV3.swift Package.swift
git commit -m "feat(supabase): expose realtimeV3 on SupabaseClient using _Realtime"
```

---

## Task 3: Integration tests

**Files:**
- Create: `Tests/IntegrationTests/RealtimeV3IntegrationTests.swift`

Integration tests require `supabase start` from within `Tests/IntegrationTests/`.

- [ ] **Step 1: Start local Supabase**

```bash
cd Tests/IntegrationTests && supabase start
```

- [ ] **Step 2: Create integration tests**

```swift
import Testing
import _Realtime

// Integration tests require a running local Supabase instance.
// Run: cd Tests/IntegrationTests && supabase start

@Suite(.disabled("Requires local Supabase — run with INTEGRATION=1"))
struct RealtimeV3IntegrationTests {
  static let url = URL(string: ProcessInfo.processInfo.environment["SUPABASE_REALTIME_URL"]
    ?? "ws://localhost:54321/realtime/v1")!
  static let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
    ?? "your-anon-key-here"

  func makeRealtime() -> Realtime {
    Realtime(url: Self.url, apiKey: .literal(Self.anonKey))
  }

  @Test func connectAndDisconnect() async throws {
    let realtime = makeRealtime()
    try await realtime.connect()
    let snapshot = await realtime.currentStatus
    #expect(snapshot == .connected)
    await realtime.disconnect()
  }

  @Test func broadcastRoundTrip() async throws {
    struct Msg: Codable, Sendable, Equatable { let text: String }
    let r1 = makeRealtime()
    let r2 = makeRealtime()

    try await r1.connect()
    try await r2.connect()

    let sender  = r1.channel("integration:broadcast")
    let receiver = r2.channel("integration:broadcast") { $0.broadcast.receiveOwnBroadcasts = false }

    var received: [Msg] = []
    Task {
      for try await msg in receiver.broadcasts(of: Msg.self, event: "test") {
        received.append(msg)
      }
    }
    try await Task.sleep(for: .milliseconds(500)) // wait for join

    try await sender.join()
    try await sender.broadcast(Msg(text: "hello integration"), as: "test")

    try await Task.sleep(for: .seconds(1))
    #expect(received.contains(Msg(text: "hello integration")))

    try await sender.leave()
    try await receiver.leave()
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add Tests/IntegrationTests/RealtimeV3IntegrationTests.swift
git commit -m "test: add Realtime v3 integration test scaffold"
```

---

## Task 4: Migration guide

**Files:**
- Create: `docs/migrations/RealtimeV3 Migration Guide.md`

- [ ] **Step 1: Create the migration guide**

```markdown
# Realtime V2 → V3 Migration Guide

Realtime V3 (`_Realtime`) is a greenfield redesign targeting Swift 6.0+ and iOS 17+.
Import it with `import _Realtime` (renamed to `import Realtime` at final release).

## Quick-reference mapping

| V2 | V3 |
|----|-----|
| `import Realtime` | `import _Realtime` |
| `RealtimeClientV2(url:options:)` | `Realtime(url:apiKey:configuration:transport:)` |
| `client.channel("x", options: …)` | `realtime.channel("x") { $0.isPrivate = true }` |
| `await channel.subscribe()` | Implicit on first `broadcasts()` / `changes()` iteration |
| `await channel.unsubscribe()` | `try await channel.leave()` |
| `channel.broadcastStream(event:)` | `channel.broadcasts(of: T.self, event:)` |
| `await channel.broadcast(event:message:)` | `try await channel.broadcast(payload, as: event)` |
| `channel.postgresChange(.all, schema:table:filter:)` | `channel.changes(to: T.self, where: .eq(\.col, val))` |
| `channel.presenceChange()` | `channel.presence.diffs(T.self)` |
| `channel.track(state:)` | `try await channel.presence.track(state)` → `PresenceHandle` |
| `ObservationToken` / `subscription.cancel()` | Task cancellation ends `AsyncThrowingStream` iteration |
| `accessToken: () async -> String?` | `APIKeySource.dynamic { … }` |
| `any Error` at boundaries | `throws(RealtimeError)` everywhere |
| `RealtimeClientOptions.maxRetryAttempts` | `Configuration.reconnection: ReconnectionPolicy` |

## Key behavioural differences

### Explicit `leave()` — no auto-unsubscribe

V2 unsubscribed on `ObservationToken` deallocation. V3 requires an explicit `try await channel.leave()`.
The channel is shared within a `Realtime` instance — `leave()` tears it down for **all** holders.

### Channels shared by topic

`realtime.channel("room:1")` always returns the same actor regardless of how many times it's called.
One server-side subscription per topic per `Realtime` instance.

### `broadcast()` requires a joined channel

`try await channel.broadcast(…)` throws `.channelNotJoined` if the channel hasn't joined.
For one-shot sends without joining, use `realtime.httpBroadcast(topic:event:payload:)`.

### Stream lifecycle

V2 callback-based: `channel.onBroadcast(event:) { … }` returning `ObservationToken`.
V3 `AsyncThrowingStream`: `for try await msg in channel.broadcasts(of: T.self, event: "chat") { … }`.
Cancel by cancelling the enclosing `Task`.

### Typed errors

Every throwing API uses `throws(RealtimeError)`. Call sites can switch exhaustively:
```swift
do {
  try await channel.broadcast(msg, as: "event")
} catch let error as RealtimeError {
  switch error {
  case .channelNotJoined: …
  case .disconnected: …
  default: …
  }
}
```
```

- [ ] **Step 2: Commit**

```bash
git add "docs/migrations/RealtimeV3 Migration Guide.md"
git commit -m "docs: add Realtime V2 → V3 migration guide"
```

---

## Task 5: Final validation

- [ ] **Step 1: Run all `_Realtime` tests**

```bash
cd Packages/_Realtime && swift test
```

Expected: All tests pass, 0 failures.

- [ ] **Step 2: Run all `_RealtimeTableMacros` tests**

```bash
cd Packages/_RealtimeTableMacros && swift test
```

Expected: All tests pass.

- [ ] **Step 3: Build root package (all targets)**

```bash
swift build
```

Expected: Build succeeded, no errors.

- [ ] **Step 4: Run existing test suite — verify no regressions**

```bash
swift test --filter RealtimeTests
swift test --filter AuthTests
swift test --filter SupabaseTests
```

Expected: All pass. Existing `Realtime` (V2) module untouched.

- [ ] **Step 5: Final commit**

```bash
git add .
git commit -m "feat: Realtime v3 — _Realtime package complete, all phases integrated"
```
