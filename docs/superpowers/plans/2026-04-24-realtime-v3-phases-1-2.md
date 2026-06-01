# Realtime v3 — Phase 1 & 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `Packages/_Realtime` Swift package with foundation types (Phase 1) and deterministic test infrastructure (Phase 2).

**Architecture:** Standalone Swift 6.0 package at `Packages/_Realtime/`. Phase 1 defines pure value types — errors, transport protocol, configuration. Phase 2 adds `InMemoryTransport.pair()` that enables all future phases to test without real sockets.

**Tech Stack:** Swift 6.0, swift-clocks, swift-concurrency-extras, xctest-dynamic-overlay, URLSessionWebSocketTask

---

## Task 1: Package scaffold

**Files:**
- Create: `Packages/_Realtime/Package.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/.gitkeep`
- Create: `Packages/_Realtime/Tests/_RealtimeTests/.gitkeep`

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p Packages/_Realtime/Sources/_Realtime/{Error,Transport,Config,Testing,Internal,Client,Channel,Broadcast,Presence,Postgres,Macros}
mkdir -p Packages/_Realtime/Tests/_RealtimeTests
```

- [ ] **Step 2: Create `Packages/_Realtime/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "_Realtime",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .tvOS(.v17),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "_Realtime", targets: ["_Realtime"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.2.2"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.2"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
  ],
  targets: [
    .target(
      name: "_Realtime",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("ExistentialAny"),
      ]
    ),
    .testTarget(
      name: "_RealtimeTests",
      dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "_Realtime",
      ]
    ),
  ]
)
```

- [ ] **Step 3: Verify package resolves**

```bash
cd Packages/_Realtime && swift package resolve
```

Expected: Dependencies download without errors.

---

## Task 2: Error types

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Error/RealtimeError.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Error/RealtimeLogger.swift`

- [ ] **Step 1: Create `Error/RealtimeError.swift`**

```swift
import Foundation

public enum RealtimeError: Error, Sendable {
  // Connection
  case disconnected
  case transportFailure(underlying: any Error & Sendable)
  case reconnectionGaveUp(lastError: any Error & Sendable)

  // Channel lifecycle
  case channelNotJoined
  case channelJoinTimeout
  case channelJoinRejected(reason: String)
  case channelClosed(CloseReason)

  // Auth
  case authenticationFailed(reason: String, underlying: (any Error & Sendable)?)
  case tokenExpired

  // Server
  case rateLimited(retryAfter: Duration?)
  case serverError(code: Int, message: String)

  // Broadcast
  case broadcastFailed(reason: String)
  case broadcastAckTimeout

  // Coding
  case decoding(type: String, underlying: any Error & Sendable)
  case encoding(underlying: any Error & Sendable)

  // Cancellation (Swift CancellationError folded here)
  case cancelled
}

public enum CloseReason: Sendable, Equatable {
  case userRequested
  case serverClosed(code: Int, message: String?)
  case timeout
  case unauthorized
  case policyViolation(String)
  case transportFailure
}
```

- [ ] **Step 2: Create `Error/RealtimeLogger.swift`**

```swift
import Foundation

public protocol RealtimeLogger: Sendable {
  func log(_ event: LogEvent)
}

public struct LogEvent: Sendable {
  public let level: LogLevel
  public let category: LogCategory
  public let message: String
  public let metadata: [String: String]
  public let timestamp: Date

  public init(
    level: LogLevel,
    category: LogCategory,
    message: String,
    metadata: [String: String] = [:],
    timestamp: Date = Date()
  ) {
    self.level = level
    self.category = category
    self.message = message
    self.metadata = metadata
    self.timestamp = timestamp
  }
}

public enum LogLevel: Sendable { case debug, info, warn, error }
public enum LogCategory: Sendable { case connection, channel, broadcast, presence, postgres }
```

---

## Task 3: Transport protocol + URLSessionTransport

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Transport/RealtimeTransport.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Transport/URLSessionTransport.swift`

- [ ] **Step 1: Create `Transport/RealtimeTransport.swift`**

```swift
import Foundation

public protocol RealtimeTransport: Sendable {
  func connect(to url: URL, headers: [String: String]) async throws -> any RealtimeConnection
}

public protocol RealtimeConnection: Sendable {
  /// Incoming frames from the server. Finishes (possibly with error) when the connection closes.
  var frames: AsyncThrowingStream<TransportFrame, any Error> { get }
  func send(_ frame: TransportFrame) async throws
  func close(code: Int, reason: String) async
}

public enum TransportFrame: Sendable, Equatable {
  case text(String)
  case binary(Data)
}
```

- [ ] **Step 2: Create `Transport/URLSessionTransport.swift`**

```swift
import Foundation

public struct URLSessionTransport: RealtimeTransport {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func connect(to url: URL, headers: [String: String]) async throws -> any RealtimeConnection {
    var request = URLRequest(url: url)
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    let task = session.webSocketTask(with: request)
    task.resume()
    return URLSessionConnection(task: task)
  }
}

private final class URLSessionConnection: RealtimeConnection, @unchecked Sendable {
  private let task: URLSessionWebSocketTask
  let frames: AsyncThrowingStream<TransportFrame, any Error>
  private let continuation: AsyncThrowingStream<TransportFrame, any Error>.Continuation

  init(task: URLSessionWebSocketTask) {
    self.task = task
    let (stream, cont) = AsyncThrowingStream<TransportFrame, any Error>.makeStream()
    self.frames = stream
    self.continuation = cont
    startReceiving()
  }

  private func startReceiving() {
    let task = self.task
    let continuation = self.continuation
    Task {
      do {
        while true {
          let message = try await task.receive()
          switch message {
          case .string(let text): continuation.yield(.text(text))
          case .data(let data):   continuation.yield(.binary(data))
          @unknown default:       break
          }
        }
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }

  func send(_ frame: TransportFrame) async throws {
    switch frame {
    case .text(let text): try await task.send(.string(text))
    case .binary(let data): try await task.send(.data(data))
    }
  }

  func close(code: Int, reason: String) async {
    task.cancel(with: .normalClosure, reason: reason.data(using: .utf8))
  }
}
```

---

## Task 4: Configuration types

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Config/APIKeySource.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Config/ReconnectionPolicy.swift`
- Create: `Packages/_Realtime/Sources/_Realtime/Config/Configuration.swift`

- [ ] **Step 1: Create `Config/APIKeySource.swift`**

```swift
public enum APIKeySource: Sendable {
  case literal(String)
  /// Called on connect and on `token_expired` server signal.
  case dynamic(@Sendable () async throws -> String)
}
```

- [ ] **Step 2: Create `Config/ReconnectionPolicy.swift`**

```swift
import Foundation

public struct ReconnectionPolicy: Sendable {
  /// Return `nil` to stop retrying.
  public var nextDelay: @Sendable (_ attempt: Int, _ lastError: any Error & Sendable) -> Duration?

  public static let never = ReconnectionPolicy { _, _ in nil }

  public static func exponentialBackoff(
    initial: Duration,
    max: Duration,
    jitter: Double = 0.2
  ) -> ReconnectionPolicy {
    let initialSecs = Double(initial.components.seconds)
    let maxSecs = Double(max.components.seconds)
    return ReconnectionPolicy { attempt, _ in
      let base = initialSecs * pow(2.0, Double(attempt - 1))
      let capped = Swift.min(base, maxSecs)
      let noise = capped * Double.random(in: -jitter...jitter)
      return .seconds(Swift.max(0, capped + noise))
    }
  }

  public static func fixed(_ delay: Duration, maxAttempts: Int? = nil) -> ReconnectionPolicy {
    ReconnectionPolicy { attempt, _ in
      if let max = maxAttempts, attempt > max { return nil }
      return delay
    }
  }
}
```

- [ ] **Step 3: Create `Config/Configuration.swift`**

```swift
import Clocks
import Foundation

public struct Configuration: Sendable {
  public var heartbeat: Duration = .seconds(25)
  public var joinTimeout: Duration = .seconds(10)
  public var leaveTimeout: Duration = .seconds(10)
  public var broadcastAckTimeout: Duration = .seconds(5)
  public var reconnection: ReconnectionPolicy = .exponentialBackoff(
    initial: .seconds(1), max: .seconds(30)
  )
  /// Socket stays open this long after the last channel leaves. `.zero` = immediate close.
  public var disconnectOnEmptyChannelsAfter: Duration = .seconds(50)
  public var handleAppLifecycle: Bool = Configuration.defaultHandleAppLifecycle
  public var protocolVersion: RealtimeProtocolVersion = .v2
  public var clock: any Clock<Duration> = ContinuousClock()
  public var headers: [String: String] = [:]
  public var logger: (any RealtimeLogger)? = nil
  public var decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()
  public var encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
  }()

  public static let `default` = Configuration()
  public init() {}

  #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
  static let defaultHandleAppLifecycle = true
  #else
  static let defaultHandleAppLifecycle = false
  #endif
}

public enum RealtimeProtocolVersion: String, Sendable {
  case v1 = "1.0.0"
  case v2 = "2.0.0"
}
```

---

## Task 5: Phase 1 tests + build

**Files:**
- Create: `Packages/_Realtime/Tests/_RealtimeTests/ReconnectionPolicyTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import Testing
@testable import _Realtime

@Suite struct ReconnectionPolicyTests {
  @Test func neverPolicyReturnsNilImmediately() {
    let policy = ReconnectionPolicy.never
    let delay = policy.nextDelay(1, URLError(.notConnectedToInternet))
    #expect(delay == nil)
  }

  @Test func fixedPolicyReturnsDelayUntilMax() {
    let policy = ReconnectionPolicy.fixed(.seconds(2), maxAttempts: 3)
    #expect(policy.nextDelay(1, URLError(.notConnectedToInternet)) == .seconds(2))
    #expect(policy.nextDelay(3, URLError(.notConnectedToInternet)) == .seconds(2))
    #expect(policy.nextDelay(4, URLError(.notConnectedToInternet)) == nil)
  }

  @Test func exponentialBackoffGrowsWithAttempts() {
    let policy = ReconnectionPolicy.exponentialBackoff(
      initial: .seconds(1), max: .seconds(16), jitter: 0
    )
    let d1 = policy.nextDelay(1, URLError(.notConnectedToInternet))!
    let d2 = policy.nextDelay(2, URLError(.notConnectedToInternet))!
    let d3 = policy.nextDelay(3, URLError(.notConnectedToInternet))!
    #expect(d1.components.seconds == 1)
    #expect(d2.components.seconds == 2)
    #expect(d3.components.seconds == 4)
  }

  @Test func exponentialBackoffCapsAtMax() {
    let policy = ReconnectionPolicy.exponentialBackoff(
      initial: .seconds(1), max: .seconds(5), jitter: 0
    )
    let d10 = policy.nextDelay(10, URLError(.notConnectedToInternet))!
    #expect(d10.components.seconds <= 5)
  }
}
```

- [ ] **Step 2: Run test — expect compile success, tests pass**

```bash
cd Packages/_Realtime && swift test --filter ReconnectionPolicyTests
```

Expected: All 4 tests pass.

- [ ] **Step 3: Build the full target**

```bash
cd Packages/_Realtime && swift build
```

Expected: Build succeeded, 0 errors.

- [ ] **Step 4: Commit**

```bash
git add Packages/_Realtime
git commit -m "feat(_Realtime): Phase 1 — foundation types (error, transport, config)"
```

---

## Task 6: InMemoryTransport (Phase 2)

**Files:**
- Create: `Packages/_Realtime/Sources/_Realtime/Testing/InMemoryTransport.swift`

- [ ] **Step 1: Write failing test first**

Create `Packages/_Realtime/Tests/_RealtimeTests/TransportTests.swift`:

```swift
import Testing
import ConcurrencyExtras
@testable import _Realtime

@Suite struct TransportTests {
  @Test func framesFlowClientToServer() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let connection = try await transport.connect(to: URL(string: "ws://test")!, headers: [:])

    try await connection.send(.text("hello"))
    let received = await server.receive()
    #expect(received == .text("hello"))
  }

  @Test func framesFlowServerToClient() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let connection = try await transport.connect(to: URL(string: "ws://test")!, headers: [:])

    Task { await server.send(.text("from server")) }

    var iter = connection.frames.makeAsyncIterator()
    let frame = try await iter.next()
    #expect(frame == .text("from server"))
  }

  @Test func serverCloseFinishesClientFrames() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let connection = try await transport.connect(to: URL(string: "ws://test")!, headers: [:])

    Task { await server.close() }

    var receivedFrames: [TransportFrame] = []
    do {
      for try await frame in connection.frames {
        receivedFrames.append(frame)
      }
    } catch {
      // close with error is fine
    }
    // Stream ended — either normally or with error
    #expect(receivedFrames.isEmpty)
  }
}
```

- [ ] **Step 2: Run test — expect compile failure (InMemoryTransport not defined)**

```bash
cd Packages/_Realtime && swift test --filter TransportTests 2>&1 | head -20
```

Expected: error: cannot find type 'InMemoryTransport'

- [ ] **Step 3: Create `Testing/InMemoryTransport.swift`**

```swift
import Foundation

/// A paired in-memory transport for deterministic tests. No real I/O.
///
/// Usage:
/// ```swift
/// let (transport, server) = InMemoryTransport.pair()
/// let realtime = Realtime(url: testURL, apiKey: .literal("key"), transport: transport)
/// ```
public final class InMemoryTransport: RealtimeTransport, @unchecked Sendable {
  // server → client
  private let (serverToClientStream, serverToClientCont) =
    AsyncThrowingStream<TransportFrame, any Error>.makeStream()
  // client → server
  private let (clientToServerStream, clientToServerCont) =
    AsyncThrowingStream<TransportFrame, any Error>.makeStream()

  private init() {}

  public static func pair() -> (client: InMemoryTransport, server: InMemoryServer) {
    let t = InMemoryTransport()
    let s = InMemoryServer(
      receivedFrames: t.clientToServerStream,
      sendContinuation: t.serverToClientCont
    )
    return (t, s)
  }

  public func connect(to url: URL, headers: [String: String]) async throws -> any RealtimeConnection {
    InMemoryConnection(
      inbound: serverToClientStream,
      outbound: clientToServerCont
    )
  }
}

/// The server side of an `InMemoryTransport` pair.
public final class InMemoryServer: Sendable {
  private let receivedFrames: AsyncThrowingStream<TransportFrame, any Error>
  private let sendContinuation: AsyncThrowingStream<TransportFrame, any Error>.Continuation

  init(
    receivedFrames: AsyncThrowingStream<TransportFrame, any Error>,
    sendContinuation: AsyncThrowingStream<TransportFrame, any Error>.Continuation
  ) {
    self.receivedFrames = receivedFrames
    self.sendContinuation = sendContinuation
  }

  /// Awaits the next frame the client sent.
  public func receive() async -> TransportFrame? {
    try? await receivedFrames.first(where: { _ in true })
  }

  /// Push a frame to the client.
  public func send(_ frame: TransportFrame) async {
    sendContinuation.yield(frame)
  }

  /// Simulate server-initiated close (with error).
  public func close(code: Int = 1000, reason: String = "") {
    sendContinuation.finish(throwing: URLError(.networkConnectionLost))
  }
}

private struct InMemoryConnection: RealtimeConnection, Sendable {
  let frames: AsyncThrowingStream<TransportFrame, any Error>
  private let outbound: AsyncThrowingStream<TransportFrame, any Error>.Continuation

  init(
    inbound: AsyncThrowingStream<TransportFrame, any Error>,
    outbound: AsyncThrowingStream<TransportFrame, any Error>.Continuation
  ) {
    self.frames = inbound
    self.outbound = outbound
  }

  func send(_ frame: TransportFrame) async throws {
    outbound.yield(frame)
  }

  func close(code: Int, reason: String) async {
    outbound.finish()
  }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
cd Packages/_Realtime && swift test --filter TransportTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/_Realtime/Sources/_Realtime/Testing \
        Packages/_Realtime/Tests/_RealtimeTests/TransportTests.swift
git commit -m "feat(_Realtime): Phase 2 — InMemoryTransport test infrastructure"
```

---

## Task 7: Wire `_Realtime` into the main package

**Files:**
- Modify: `Package.swift` (root)

- [ ] **Step 1: Add local package dependency and product to root `Package.swift`**

Add to the `dependencies` array:
```swift
.package(path: "Packages/_Realtime"),
```

Add to the `products` array:
```swift
.library(name: "_Realtime", targets: ["_Realtime"]),
```

The root package doesn't need to depend on `_Realtime` in any existing target yet — that comes in Phase 8. This step just makes the package resolvable from the root.

- [ ] **Step 2: Verify root package still builds**

```bash
swift build
```

Expected: Build succeeded. Existing targets unaffected.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "chore: wire Packages/_Realtime into root package as local dependency"
```
