# Realtime WebSocket Certificate Pinning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let apps pin the Realtime WebSocket connection using the same `URLSessionDelegate` they already use for Auth/PostgREST/Storage, by reusing the SDK's existing `session: URLSession` injection idiom instead of adding a single-purpose closure.

**Architecture:** `RealtimeClientOptions` gains a `session: URLSession` property (default `.shared`, package-settable, same shape as `StorageHTTPSession`/`SupabaseClientOptions.global.session`). `URLSessionWebSocket.connect` uses that session directly to create its `URLSessionWebSocketTask` and assigns a per-task delegate (`URLSessionTask.delegate`, available on all Apple platforms this package targets) that forwards only the auth-challenge callback to the session's own delegate — WebSocket lifecycle callbacks (open/close/complete) stay owned internally. `SupabaseClient` auto-propagates `configuration.global.session` into Realtime, so apps that already pin `global.session` get Realtime pinning for free.

**Tech Stack:** Swift 6.1+, Foundation `URLSession`/`URLSessionWebSocketTask`, `ConcurrencyExtras` (`LockIsolated`), XCTest (existing `WebSocketTests.swift`), Swift Testing (`Testing` framework, new/existing Swift-Testing files).

**Spec:** [docs/superpowers/specs/2026-07-13-realtime-websocket-cert-pinning-design.md](../specs/2026-07-13-realtime-websocket-cert-pinning-design.md)

## Global Constraints

- Fully additive — no breaking changes to `RealtimeClientOptions` or `RealtimeClientV2` public API.
- `URLSessionTask.delegate` may not exist in swift-corelibs-foundation (Linux). Linux is build-only for this package (not production-supported per `AGENTS.md`) — guard with `#if canImport(FoundationNetworking)` and preserve today's session-level-delegate behavior there (WebSocket lifecycle must keep working on Linux; only the pinning-forwarding path is Apple-platform-only).
- Run `./scripts/format.sh` before each commit (repo convention).
- New test files use Swift Testing (`@Suite`/`@Test`/`#expect`); edits to existing XCTest files (`WebSocketTests.swift`) stay XCTest, per `AGENTS.md`'s per-file migration rule.
- `RealtimeClientOptions.session` (like `fetch`/`accessToken`/`logger`) is `package var`, not `public var` — settable only via the public initializer, not mutable externally after construction.
- The Task 3 e2e test shells out to `/usr/bin/openssl` via `Process` to generate a throwaway self-signed certificate; gate it to `#if os(macOS)` since `Process` is unavailable on iOS/tvOS/watchOS simulator test destinations.
- `URLSessionWebSocket.connect`'s `session:` parameter defaults to `.shared`, but `connect` must only use the caller's session directly (enabling pinning) when it's *not* `.shared` — when left at the default, build a dedicated internal session exactly as before (see Task 2 Step 8's rationale). This keeps the common no-session-specified case immune to process-wide `URLSession` state (global `URLProtocol` registrations, etc.), matching pre-existing behavior; pinning activates only when a caller opts in with their own session.

---

### Task 1: `RealtimeClientOptions.session`

**Files:**
- Modify: `Sources/RealtimeV2/Types.swift:61` (DocC init symbol reference), `:96-97` (property), `:150-182` (init)
- Test: Create `Tests/RealtimeTests/RealtimeClientOptionsTests.swift`

**Interfaces:**
- Produces: `RealtimeClientOptions.session: URLSession` (package-visible property), new init parameter `session: URLSession = .shared` inserted between `logger` and `handleAppLifecycle`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/RealtimeTests/RealtimeClientOptionsTests.swift`:

```swift
import Foundation
import Testing

@testable import RealtimeV2

@Suite
struct RealtimeClientOptionsTests {
  @Test
  func sessionDefaultsToShared() {
    let options = RealtimeClientOptions(headers: ["apikey": "test-key"])
    #expect(options.session === URLSession.shared)
  }

  @Test
  func sessionCanBeOverridden() {
    let customSession = URLSession(configuration: .ephemeral)
    let options = RealtimeClientOptions(
      headers: ["apikey": "test-key"],
      session: customSession
    )
    #expect(options.session === customSession)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RealtimeClientOptionsTests`
Expected: FAIL — `value of type 'RealtimeClientOptions' has no member 'session'`

- [ ] **Step 3: Add the `session` property and init parameter**

In `Sources/RealtimeV2/Types.swift`, add the property right after `package var logger: (any SupabaseLogger)?` (currently line 97):

```swift
  package var logger: (any SupabaseLogger)?

  /// The `URLSession` used to establish the Realtime WebSocket connection.
  ///
  /// Pass the same preconfigured `URLSession` used elsewhere in your app (e.g. one with a
  /// `URLSessionDelegate` implementing certificate pinning) to apply the same trust
  /// evaluation to Realtime's WebSocket connection. Defaults to `URLSession.shared`.
  package var session: URLSession
```

Update the primary initializer (currently lines 152-182) to accept and store `session`, inserted between `logger` and `handleAppLifecycle`:

```swift
  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    disconnectOnEmptyChannelsAfter: TimeInterval = Self.defaultDisconnectOnEmptyChannelsAfter,
    vsn: RealtimeProtocolVersion = .v2,
    logLevel: LogLevel? = nil,
    fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: (any SupabaseLogger)? = nil,
    session: URLSession = .shared,
    handleAppLifecycle: Bool = Self.defaultHandleAppLifecycle
  ) {
    self.headers = HTTPFields(headers)
    self.heartbeatInterval = heartbeatInterval
    self.reconnectDelay = reconnectDelay
    self.timeoutInterval = timeoutInterval
    self.disconnectOnSessionLoss = disconnectOnSessionLoss
    self.connectOnSubscribe = connectOnSubscribe
    self.maxRetryAttempts = maxRetryAttempts
    self.disconnectOnEmptyChannelsAfter = disconnectOnEmptyChannelsAfter
    self.vsn = vsn
    self.handleAppLifecycle = handleAppLifecycle
    self.logLevel = logLevel
    self.fetch = fetch
    self.accessToken = accessToken
    self.logger = logger
    self.session = session
  }
```

Do **not** change the `@_disfavoredOverload` backward-compatible initializer (lines 184-216) — it calls through to the primary initializer, which supplies `session`'s default automatically.

Update the DocC comment above the primary initializer: add a parameter line after the `logger:` line (currently around line 150):

```swift
  ///   - logger: Optional logger conforming to `SupabaseLogger`.
  ///   - session: The `URLSession` used for the WebSocket connection. Defaults to `URLSession.shared`.
  ///   - handleAppLifecycle: Whether to automatically reconnect on app foreground. Defaults to ``defaultHandleAppLifecycle``.
```

Update the struct-level DocC `## Topics ### Initialization` symbol reference (currently line 61) to match the new signature:

```swift
/// - ``init(headers:heartbeatInterval:reconnectDelay:timeoutInterval:disconnectOnSessionLoss:connectOnSubscribe:maxRetryAttempts:disconnectOnEmptyChannelsAfter:vsn:logLevel:fetch:accessToken:logger:session:handleAppLifecycle:)``
```

Do not add a `- ``session``` bullet to the `### Default Values` or any other public Topics list — `session` is `package`-visible, not `public`, and DocC will warn on a link to a non-public symbol (same reason `fetch`/`accessToken`/`logger` aren't listed there today).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RealtimeClientOptionsTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
./scripts/format.sh
git add Sources/RealtimeV2/Types.swift Tests/RealtimeTests/RealtimeClientOptionsTests.swift
git commit -m "feat(realtime): add session option to RealtimeClientOptions"
```

---

### Task 2: `URLSessionWebSocket` per-task delegate forwarding

**Files:**
- Modify: `Sources/RealtimeV2/WebSocket/URLSessionWebSocket.swift`
- Test: Modify `Tests/RealtimeTests/WebSocketTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 (this task is independent; `URLSessionWebSocket.connect` takes its own `session` parameter directly).
- Produces: `URLSessionWebSocket.connect(to:protocols:headers:session:)` (replaces the `configuration:` parameter), `_Delegate.init(onComplete:onWebSocketTaskOpened:onWebSocketTaskClosed:wrappedDelegate:)` (new `wrappedDelegate: (any URLSessionDelegate)? = nil` parameter), `_Delegate.urlSession(_:task:didReceive:completionHandler:)` (new method).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/RealtimeTests/WebSocketTests.swift`, inside `final class WebSocketTests: XCTestCase { ... }`, after the existing `// MARK: - URLSessionWebSocket Lifecycle Tests` block (before the closing brace at line 129):

```swift
  // MARK: - _Delegate Auth Challenge Forwarding Tests

  private func makeChallenge() -> URLAuthenticationChallenge {
    let protectionSpace = URLProtectionSpace(
      host: "example.com", port: 443, protocol: "https", realm: nil,
      authenticationMethod: NSURLAuthenticationMethodServerTrust)
    return URLAuthenticationChallenge(
      protectionSpace: protectionSpace, proposedCredential: nil, previousFailureCount: 0,
      failureResponse: nil, error: nil)
  }

  func testChallengeForwardedToTaskLevelWrappedDelegate() {
    final class TaskDelegate: NSObject, URLSessionTaskDelegate {
      var receivedChallenge: URLAuthenticationChallenge?
      func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
        receivedChallenge = challenge
        completionHandler(.useCredential, nil)
      }
    }

    let wrappedDelegate = TaskDelegate()
    let delegate = _Delegate(
      onComplete: nil,
      onWebSocketTaskOpened: nil,
      onWebSocketTaskClosed: nil,
      wrappedDelegate: wrappedDelegate
    )

    let session = URLSession(configuration: .default)
    let task = session.dataTask(with: URL(string: "https://example.com")!)
    let challenge = makeChallenge()

    let expectation = expectation(description: "completion handler called")
    delegate.urlSession(session, task: task, didReceive: challenge) { disposition, _ in
      XCTAssertEqual(disposition, .useCredential)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    XCTAssertNotNil(wrappedDelegate.receivedChallenge)
  }

  func testChallengeForwardedToSessionLevelWrappedDelegateWhenTaskLevelNotImplemented() {
    final class LegacyDelegate: NSObject, URLSessionDelegate {
      var receivedChallenge: URLAuthenticationChallenge?
      func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
        receivedChallenge = challenge
        completionHandler(.cancelAuthenticationChallenge, nil)
      }
    }

    let wrappedDelegate = LegacyDelegate()
    let delegate = _Delegate(
      onComplete: nil,
      onWebSocketTaskOpened: nil,
      onWebSocketTaskClosed: nil,
      wrappedDelegate: wrappedDelegate
    )

    let session = URLSession(configuration: .default)
    let task = session.dataTask(with: URL(string: "https://example.com")!)
    let challenge = makeChallenge()

    let expectation = expectation(description: "completion handler called")
    delegate.urlSession(session, task: task, didReceive: challenge) { disposition, _ in
      XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    XCTAssertNotNil(wrappedDelegate.receivedChallenge)
  }

  func testChallengeDefaultsToPerformDefaultHandlingWhenNoWrappedDelegate() {
    let delegate = _Delegate(
      onComplete: nil,
      onWebSocketTaskOpened: nil,
      onWebSocketTaskClosed: nil,
      wrappedDelegate: nil
    )

    let session = URLSession(configuration: .default)
    let task = session.dataTask(with: URL(string: "https://example.com")!)
    let challenge = makeChallenge()

    let expectation = expectation(description: "completion handler called")
    delegate.urlSession(session, task: task, didReceive: challenge) { disposition, credential in
      XCTAssertEqual(disposition, .performDefaultHandling)
      XCTAssertNil(credential)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WebSocketTests`
Expected: FAIL to compile — `_Delegate` has no `wrappedDelegate` parameter and no `urlSession(_:task:didReceive:completionHandler:)` method.

- [ ] **Step 3: Implement `_Delegate` challenge forwarding**

In `Sources/RealtimeV2/WebSocket/URLSessionWebSocket.swift`, replace the `_Delegate` class (currently lines 434-491) with:

```swift
// MARK: - Private Delegate

/// Internal URLSession delegate for handling WebSocket events.
///
/// This delegate handles the various WebSocket lifecycle events and forwards them
/// to the appropriate callbacks provided during URLSession creation. It also forwards
/// TLS/auth-challenge callbacks to a wrapped delegate (typically the caller's own
/// session delegate), so apps can pin certificates on the Realtime WebSocket connection
/// using the same `URLSessionDelegate` they already use elsewhere.
final class _Delegate: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate,
  URLSessionWebSocketDelegate
{
  /// Callback for task completion events.
  let onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)?
  /// Callback for WebSocket connection opened events.
  let onWebSocketTaskOpened: (@Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void)?
  /// Callback for WebSocket connection closed events.
  let onWebSocketTaskClosed: (@Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void)?
  /// The delegate captured from the caller's own `URLSession` (if any), consulted for
  /// auth-challenge forwarding only. Read-only after `init`; only ever invoked from the
  /// URLSession delegate queue, the same way `URLSession` itself would call it.
  private nonisolated(unsafe) let wrappedDelegate: (any URLSessionDelegate)?

  init(
    onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)?,
    onWebSocketTaskOpened: (
      @Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void
    )?,
    onWebSocketTaskClosed: (
      @Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void
    )?,
    wrappedDelegate: (any URLSessionDelegate)? = nil
  ) {
    self.onComplete = onComplete
    self.onWebSocketTaskOpened = onWebSocketTaskOpened
    self.onWebSocketTaskClosed = onWebSocketTaskClosed
    self.wrappedDelegate = wrappedDelegate
  }

  /// Called when a task completes, with or without error.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    onComplete?(session, task, error)
  }

  /// Called when a WebSocket connection is successfully established.
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    onWebSocketTaskOpened?(session, webSocketTask, `protocol`)
  }

  /// Called when a WebSocket connection is closed.
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    onWebSocketTaskClosed?(session, webSocketTask, closeCode.rawValue, reason)
  }

  /// Forwards the task-level auth challenge to `wrappedDelegate`, trying its task-level
  /// implementation first, then falling back to its session-level implementation, then to
  /// default handling. Always calls `completionHandler` exactly once.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard let wrappedDelegate else {
      completionHandler(.performDefaultHandling, nil)
      return
    }

    let taskLevelSelector = #selector(
      URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:))
    if let taskDelegate = wrappedDelegate as? URLSessionTaskDelegate,
      wrappedDelegate.responds(to: taskLevelSelector)
    {
      taskDelegate.urlSession?(
        session, task: task, didReceive: challenge, completionHandler: completionHandler)
      return
    }

    let sessionLevelSelector = #selector(
      URLSessionDelegate.urlSession(_:didReceive:completionHandler:))
    if wrappedDelegate.responds(to: sessionLevelSelector) {
      wrappedDelegate.urlSession?(
        session, didReceive: challenge, completionHandler: completionHandler)
      return
    }

    completionHandler(.performDefaultHandling, nil)
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WebSocketTests`
Expected: PASS (all `_Delegate` forwarding tests; existing lifecycle tests unaffected)

- [ ] **Step 5: Commit**

```bash
./scripts/format.sh
git add Sources/RealtimeV2/WebSocket/URLSessionWebSocket.swift Tests/RealtimeTests/WebSocketTests.swift
git commit -m "feat(realtime): forward WebSocket auth challenges to a wrapped delegate"
```

- [ ] **Step 6: Write the failing test for `connect(session:)`**

Add to `Tests/RealtimeTests/WebSocketTests.swift`, inside the `#if canImport(Network)` block, after `testSocketsDeallocateAfterClose`:

```swift
    func testConnectUsesProvidedSessionDelegateOnNonLinuxPlatforms() async throws {
      #if canImport(FoundationNetworking)
        throw XCTSkip("per-task delegate forwarding is unavailable on Linux")
      #else
        final class RecordingDelegate: NSObject, URLSessionDelegate {}

        let server = try LoopbackWebSocketServer()
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "ws://127.0.0.1:\(port)")!
        let delegate = RecordingDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let socket = try await URLSessionWebSocket.connect(to: url, session: session)
        socket.close(code: 1000, reason: nil)
      #endif
    }
```

This asserts `connect(to:session:)` compiles and successfully connects when given an explicit `session:` with its own delegate (regression coverage for the signature change; the actual challenge-forwarding logic is already covered by the `_Delegate` unit tests above since a plain `ws://` loopback connection never triggers a TLS challenge).

- [ ] **Step 7: Run the test to verify it fails**

Run: `swift test --filter WebSocketTests/testConnectUsesProvidedSessionDelegateOnNonLinuxPlatforms`
Expected: FAIL to compile — `connect(to:)` has no `session:` parameter yet.

- [ ] **Step 8: Update `connect` to accept `session:` and assign a per-task delegate**

In `Sources/RealtimeV2/WebSocket/URLSessionWebSocket.swift`, replace the `static func connect` implementation (currently lines 58-148) with:

```swift
  static func connect(
    to url: URL,
    protocols: [String]? = nil,
    headers: [String: String]? = nil,
    session: URLSession = .shared
  ) async throws -> URLSessionWebSocket {
    guard url.scheme == "ws" || url.scheme == "wss" else {
      preconditionFailure("only ws: and wss: schemes are supported")
    }

    struct MutableState {
      var continuation: CheckedContinuation<URLSessionWebSocket, any Error>!
      var webSocket: URLSessionWebSocket?
    }

    let mutableState = LockIsolated(MutableState())

    let onComplete: @Sendable (URLSession, URLSessionTask, (any Error)?) -> Void = {
      session, task, error in
      mutableState.withValue {
        if let webSocket = $0.webSocket {
          // There are three possibilities here:
          // 1. the peer sent a close Frame, `onWebSocketTaskClosed` was already
          //    called and `_connectionClosed` is a no-op.
          // 2. we sent a close Frame (through `close()`) and `_connectionClosed`
          //    is a no-op.
          // 3. an error occurred (e.g. network failure) and `_connectionClosed`
          //    will signal that and close `event`.
          webSocket._connectionClosed(
            code: 1006,
            reason: Data("abnormal close".utf8)
          )
        } else if let error {
          $0.continuation.resume(
            throwing: WebSocketError.connection(
              message: "connection ended unexpectedly",
              error: error
            )
          )
        } else {
          // `onWebSocketTaskOpened` should have been called and resumed continuation.
          // So either there was an error creating the connection or a logic error.
          assertionFailure(
            "expected an error or `onWebSocketTaskOpened` to have been called first"
          )
        }
      }
    }
    let onWebSocketTaskOpened: @Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void = {
      session, task, `protocol` in
      mutableState.withValue {
        $0.webSocket = URLSessionWebSocket(
          _task: task, _protocol: `protocol` ?? "", session: session)
        $0.continuation.resume(returning: $0.webSocket!)
      }
    }
    let onWebSocketTaskClosed: @Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void =
      { session, task, code, reason in
        mutableState.withValue {
          assert($0.webSocket != nil, "connection should exist by this time")
          $0.webSocket!._connectionClosed(code: code, reason: reason)
        }
      }

    func makeTask(on session: URLSession) -> URLSessionWebSocketTask {
      if let headers, !headers.isEmpty {
        // Use URLRequest to set headers instead of httpAdditionalHeaders on the
        // URLSessionConfiguration. Setting httpAdditionalHeaders can interfere with
        // the WebSocket upgrade handshake on iOS, causing -1005 errors.
        var request = URLRequest(url: url)
        for (key, value) in headers {
          request.setValue(value, forHTTPHeaderField: key)
        }
        // session.webSocketTask(with: URLRequest) doesn't accept a protocols
        // parameter, so set the Sec-WebSocket-Protocol header manually.
        if let protocols, !protocols.isEmpty {
          request.setValue(
            protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        return session.webSocketTask(with: request)
      } else {
        return session.webSocketTask(with: url, protocols: protocols ?? [])
      }
    }

    func makeDedicatedSession() -> URLSession {
      URLSession.sessionWithConfiguration(
        session.configuration,
        onComplete: onComplete,
        onWebSocketTaskOpened: onWebSocketTaskOpened,
        onWebSocketTaskClosed: onWebSocketTaskClosed
      )
    }

    let task: URLSessionWebSocketTask
    #if canImport(FoundationNetworking)
      // swift-corelibs-foundation doesn't support per-task `URLSessionTask.delegate`
      // (needed to forward auth challenges without hijacking the caller's session-level
      // delegate). Fall back to a dedicated session with `_Delegate` attached at the
      // session level, matching this method's pre-existing behavior. Certificate-pinning
      // delegate forwarding via `session.delegate` is unavailable on Linux (build-only,
      // not a production-supported platform for this package).
      task = makeTask(on: makeDedicatedSession())
    #else
      if session === URLSession.shared {
        // No caller-supplied session: preserve pre-existing behavior exactly — build a
        // dedicated internal session isolated from process-wide `URLSession` state (e.g.
        // an app's own globally-registered `URLProtocol`, used for mocking or ad-hoc
        // interception), rather than silently routing the WebSocket handshake through
        // `.shared`. `.shared` is also `RealtimeClientOptions.session`'s own default
        // (Task 1) and the sentinel `SupabaseClient` checks against (Task 5) — this
        // identity check is consistent with both: pinning only activates when a caller
        // has actually opted in by supplying their own session.
        task = makeTask(on: makeDedicatedSession())
      } else {
        // Caller explicitly supplied their own session (e.g. one with a pinning delegate)
        // — use it directly and forward its delegate's auth-challenge callback via a
        // per-task delegate, while keeping WebSocket lifecycle callbacks internal.
        task = makeTask(on: session)
        task.delegate = _Delegate(
          onComplete: onComplete,
          onWebSocketTaskOpened: onWebSocketTaskOpened,
          onWebSocketTaskClosed: onWebSocketTaskClosed,
          wrappedDelegate: session.delegate
        )
      }
    #endif

    return try await withCheckedThrowingContinuation { continuation in
      mutableState.withValue {
        $0.continuation = continuation
      }
      task.resume()
    }
  }
```

**Why the `session === URLSession.shared` check:** an earlier version of this step used the caller-supplied `session` directly whenever one wasn't explicitly provided too (i.e. always, since the parameter defaults to `.shared`). That regresses real behavior: today, `connect` always builds its own dedicated internal session, so it's immune to process-wide `URLSession` state — e.g. any process-global `URLProtocol.registerClass(...)` registration (this repo's own test suite hits this: `Mocker`, used by `AuthTests`/`StorageTests`/`PostgRESTTests`/`FunctionsTests`, registers a `URLProtocol` that intercepts `URLSession.shared` process-wide the moment it's first touched, which reliably breaks the loopback WebSocket test once `WebSocketTests` runs after those suites in the same `swift test` process). The same risk applies in production to any host app with its own process-wide `URLProtocol` registration. Defaulting to `.shared` was fine as an API default value, but only if `connect` itself still special-cases "caller didn't customize it" to preserve the old dedicated-session behavior — pinning (bypassing that isolation) should be something a caller opts into by passing a real custom session, not an accidental side effect of the new default.

Update the class-level DocC comment (currently line 18) to match the new parameter list:

```swift
/// The connection is established asynchronously using the `connect(to:protocols:headers:session:)` method.
```

Update the method's own DocC comment (currently lines 43-57), replacing the `configuration:` parameter line with:

```swift
  ///   - session: The `URLSession` used to create the WebSocket task, when explicitly
  ///             provided (i.e. not `.shared`). Its `delegate`'s auth-challenge callbacks
  ///             (if any) are forwarded to, enabling certificate pinning and other
  ///             server-trust customization. When left at the default `.shared`, `connect`
  ///             builds its own dedicated internal session instead (unaffected by
  ///             process-wide `URLSession` state), matching this method's original behavior.
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `swift test --filter WebSocketTests`
Expected: PASS (all tests in the file, including the new `testConnectUsesProvidedSessionDelegateOnNonLinuxPlatforms`)

Also run the full suite once here (not just this file's filter) to catch cross-suite interference:

Run: `swift test`
Expected: PASS, including `testSocketsDeallocateAfterClose` — this test calls `connect(to:)` with no `session:` argument, so it exercises the `session === URLSession.shared` fallback branch above. If this fails specifically on `testSocketsDeallocateAfterClose` while the filtered run above passes, suspect cross-suite interference from another module's global `URLProtocol` registration (e.g. `Mocker`, used by `AuthTests`/`StorageTests`/`PostgRESTTests`/`FunctionsTests`) and confirm the fallback branch is actually being hit (not accidentally using `session` directly).

- [ ] **Step 10: Commit**

```bash
./scripts/format.sh
git add Sources/RealtimeV2/WebSocket/URLSessionWebSocket.swift Tests/RealtimeTests/WebSocketTests.swift
git commit -m "feat(realtime): accept an external URLSession in URLSessionWebSocket.connect"
```

---

### Task 3: End-to-end certificate pinning test over a real TLS server

This is the empirical check for the spec's core assumption: that a real TLS
handshake against a real (self-signed) server certificate actually reaches
the forwarding path exercised in Task 2, end to end — not just that
`_Delegate`'s method returns the right value when called directly. It proves
the *feature* (accept a pinned cert, reject a mismatched one) works over the
wire; it does not by itself distinguish whether iOS's task-level delegate
override or its native session-level delegate fallback is what delivered the
challenge to the caller's delegate — both are indistinguishable from the
outside, and either way the feature works.

**Files:**
- Modify: `Tests/RealtimeTests/WebSocketTests.swift`

**Interfaces:**
- Consumes: `URLSessionWebSocket.connect(to:protocols:headers:session:)` (Task 2).

**Constraints:**
- macOS only (`#if os(macOS) && canImport(Network)`) — this test shells out
  to `/usr/bin/openssl` via `Process`, which is unavailable on iOS/tvOS/
  watchOS simulator test destinations.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/RealtimeTests/WebSocketTests.swift`, inside the `#if canImport(Network)` block (after `testSocketsDeallocateAfterClose` / the `testConnectUsesProvidedSessionDelegateOnNonLinuxPlatforms` test added in Task 2):

```swift
    #if os(macOS)
      func testCertPinningAcceptsMatchingCertificate() async throws {
        let (identity, certificateData) = try makeSelfSignedIdentity()
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        let delegate = PinningSessionDelegate(expectedCertificateData: certificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let socket = try await URLSessionWebSocket.connect(to: url, session: session)
        socket.close(code: 1000, reason: nil)

        XCTAssertTrue(delegate.wasInvoked)
      }

      func testCertPinningRejectsMismatchedCertificate() async throws {
        let (identity, _) = try makeSelfSignedIdentity()
        let (_, wrongCertificateData) = try makeSelfSignedIdentity()
        let server = try LoopbackTLSWebSocketServer(identity: identity)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "wss://127.0.0.1:\(port)")!
        let delegate = PinningSessionDelegate(expectedCertificateData: wrongCertificateData)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
          _ = try await URLSessionWebSocket.connect(to: url, session: session)
          XCTFail("expected connection to fail due to certificate mismatch")
        } catch {
          // Expected: the pinning delegate rejected the server's certificate, so the
          // TLS handshake failed and `connect` threw.
        }

        XCTAssertTrue(delegate.wasInvoked)
      }
    #endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WebSocketTests`
Expected: FAIL to compile — `makeSelfSignedIdentity`, `LoopbackTLSWebSocketServer`, and `PinningSessionDelegate` don't exist yet.

- [ ] **Step 3: Add the self-signed certificate helper**

Add to `Tests/RealtimeTests/WebSocketTests.swift`, inside the `#if canImport(Network)` block, alongside `LoopbackWebSocketServer` (this only needs `os(macOS)` for the `Process`/`openssl` calls; keep it under the same `#if os(macOS)` guard used by the tests):

```swift
  #if os(macOS)
    import Security

    /// Generates a throwaway self-signed identity (private key + certificate) via the
    /// system `openssl` binary, then imports it into a `SecIdentity` for use with
    /// `NWProtocolTLS.Options`. macOS-only: relies on `Process` and `/usr/bin/openssl`,
    /// neither available on iOS/tvOS/watchOS simulator test destinations.
    private func makeSelfSignedIdentity() throws -> (identity: SecIdentity, certificateData: Data)
    {
      let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: tmpDir) }

      let keyURL = tmpDir.appendingPathComponent("key.pem")
      let certURL = tmpDir.appendingPathComponent("cert.pem")
      let p12URL = tmpDir.appendingPathComponent("identity.p12")
      let password = "test"

      func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
          throw WebSocketError.connection(
            message: "openssl \(arguments.first ?? "") failed",
            error: NSError(domain: "WebSocketTests", code: Int(process.terminationStatus))
          )
        }
      }

      try run([
        "req", "-x509", "-newkey", "rsa:2048", "-keyout", keyURL.path, "-out", certURL.path,
        "-days", "1", "-nodes", "-subj", "/CN=127.0.0.1",
      ])
      try run([
        "pkcs12", "-export", "-inkey", keyURL.path, "-in", certURL.path, "-out", p12URL.path,
        "-passout", "pass:\(password)",
      ])

      let p12Data = try Data(contentsOf: p12URL)
      var importResult: CFArray?
      let status = SecPKCS12Import(
        p12Data as CFData,
        [kSecImportExportPassphrase as String: password] as CFDictionary,
        &importResult
      )
      guard status == errSecSuccess,
        let items = importResult as? [[String: Any]],
        let identityRef = items.first?[kSecImportItemIdentity as String]
      else {
        throw WebSocketError.connection(
          message: "SecPKCS12Import failed",
          error: NSError(domain: "WebSocketTests", code: Int(status))
        )
      }
      let identity = identityRef as! SecIdentity

      var certificate: SecCertificate?
      SecIdentityCopyCertificate(identity, &certificate)
      guard let certificate else {
        throw WebSocketError.connection(
          message: "failed to extract certificate from identity",
          error: NSError(domain: "WebSocketTests", code: -1)
        )
      }

      return (identity, SecCertificateCopyData(certificate) as Data)
    }
  #endif
```

- [ ] **Step 4: Add the TLS loopback server**

Add right after `LoopbackWebSocketServer`'s closing brace, still inside `#if os(macOS)`:

```swift
  #if os(macOS)
    private final class LoopbackTLSWebSocketServer {
      private let listener: NWListener
      private let queue = DispatchQueue(label: "co.supabase.LoopbackTLSWebSocketServer")
      private var connections: [NWConnection] = []
      private var isStopped = false

      init(identity: SecIdentity) throws {
        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
          throw WebSocketError.connection(
            message: "sec_identity_create failed",
            error: NSError(domain: "LoopbackTLSWebSocketServer", code: -1)
          )
        }
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)

        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true

        let parameters = NWParameters(tls: tlsOptions, tcp: .init())
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        listener = try NWListener(using: parameters, on: .any)
      }

      func start() throws -> UInt16 {
        let ready = DispatchSemaphore(value: 0)

        listener.stateUpdateHandler = { state in
          switch state {
          case .ready, .failed:
            ready.signal()
          default:
            break
          }
        }

        listener.newConnectionHandler = { [weak self] connection in
          guard let self else { return }
          if self.isStopped {
            connection.cancel()
            return
          }
          self.connections.append(connection)
          connection.start(queue: self.queue)
          self.receive(on: connection)
        }

        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
          throw WebSocketError.connection(
            message: "loopback TLS server failed to start",
            error: NSError(domain: "LoopbackTLSWebSocketServer", code: -1)
          )
        }

        return port.rawValue
      }

      private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] _, context, _, error in
          if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
            as? NWProtocolWebSocket.Metadata, metadata.opcode == .close
          {
            let closeMetadata = NWProtocolWebSocket.Metadata(opcode: .close)
            let closeContext = NWConnection.ContentContext(
              identifier: "close", metadata: [closeMetadata])
            connection.send(
              content: nil,
              contentContext: closeContext,
              isComplete: true,
              completion: .contentProcessed { _ in connection.cancel() }
            )
            return
          }

          guard error == nil else { return }
          self?.receive(on: connection)
        }
      }

      func stop() {
        queue.sync {
          isStopped = true
          listener.cancel()
          for connection in connections { connection.cancel() }
          connections.removeAll()
        }
      }
    }
  #endif
```

- [ ] **Step 5: Add the pinning delegate**

Add right after `LoopbackTLSWebSocketServer`, still inside `#if os(macOS)`:

```swift
  #if os(macOS)
    /// Session-level pinning delegate: accepts the server's certificate only if it
    /// matches `expectedCertificateData` byte-for-byte, otherwise cancels the challenge.
    /// This mirrors the shape of a real app's pinning delegate (see the `Usage` example
    /// in the design spec).
    private final class PinningSessionDelegate: NSObject, URLSessionDelegate {
      let expectedCertificateData: Data
      private let lockedWasInvoked = LockIsolated(false)
      var wasInvoked: Bool { lockedWasInvoked.value }

      init(expectedCertificateData: Data) {
        self.expectedCertificateData = expectedCertificateData
      }

      func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
        lockedWasInvoked.setValue(true)

        guard
          challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust,
          let serverCertificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        else {
          completionHandler(.cancelAuthenticationChallenge, nil)
          return
        }

        let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data
        if serverCertificateData == expectedCertificateData {
          completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
          completionHandler(.cancelAuthenticationChallenge, nil)
        }
      }
    }
  #endif
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter WebSocketTests`
Expected: PASS — `testCertPinningAcceptsMatchingCertificate` connects successfully; `testCertPinningRejectsMismatchedCertificate` throws; both assert `delegate.wasInvoked` to confirm the challenge was actually delivered (guards against a false pass where the connection succeeds/fails for an unrelated reason).

If `testCertPinningRejectsMismatchedCertificate` fails because the connection *succeeds* despite the mismatch: this means the challenge never reached `PinningSessionDelegate` at all (e.g. `URLSession` short-circuited via a cached trust decision or the loopback TLS setup is misconfigured) — treat this as a real failure to investigate, not something to relax the test for.

- [ ] **Step 7: Commit**

```bash
./scripts/format.sh
git add Tests/RealtimeTests/WebSocketTests.swift
git commit -m "test(realtime): add e2e certificate pinning test over a real TLS server"
```

---

### Task 4: Wire `RealtimeClientV2` to pass `options.session` into `connect`

**Files:**
- Modify: `Sources/RealtimeV2/RealtimeClientV2.swift:226-231`

**Interfaces:**
- Consumes: `RealtimeClientOptions.session` (Task 1), `URLSessionWebSocket.connect(to:protocols:headers:session:)` (Task 2).

- [ ] **Step 1: Update the `wsTransport` closure**

In `Sources/RealtimeV2/RealtimeClientV2.swift`, inside `package convenience init(url:options:clock:)`, change:

```swift
      wsTransport: { url, headers in
        return try await URLSessionWebSocket.connect(
          to: url,
          headers: headers
        )
      },
```

to:

```swift
      wsTransport: { url, headers in
        return try await URLSessionWebSocket.connect(
          to: url,
          headers: headers,
          session: options.session
        )
      },
```

- [ ] **Step 2: Verify it builds and the existing suite still passes**

Run: `swift build`
Expected: builds with no errors.

Run: `swift test --filter RealtimeTests`
Expected: PASS — these tests inject a `FakeWebSocket` transport directly (bypassing `URLSessionWebSocket.connect` entirely), so this line isn't exercised by them; this step only guards against a regression in the surrounding code. The actual behavior (the right session reaching `connect`) is covered end-to-end by Task 5's tests, which check `RealtimeClientOptions.session` after going through `SupabaseClient`.

- [ ] **Step 3: Commit**

```bash
./scripts/format.sh
git add Sources/RealtimeV2/RealtimeClientV2.swift
git commit -m "feat(realtime): pass RealtimeClientOptions.session to the WebSocket transport"
```

---

### Task 5: Propagate `SupabaseClientOptions.global.session` into Realtime

**Files:**
- Modify: `Sources/Supabase/SupabaseClient.swift:488-522` (`_initRealtimeClient`)
- Test: Modify `Tests/SupabaseTests/SupabaseClientTests.swift`

**Interfaces:**
- Consumes: `RealtimeClientOptions.session` (Task 1).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/SupabaseTests/SupabaseClientTests.swift`, right after the existing `userProvidedRealtimeFetchIsNotOverridden` test (currently ending at line 199):

```swift
  @Test
  func globalSessionPropagatedToRealtimeWebSocket() {
    let localStorage = AuthLocalStorageMock()
    let customSession = URLSession(configuration: .ephemeral)
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: customSession)
      )
    )

    #expect(
      client.realtimeV2.options.session === customSession,
      "global URLSession should be propagated to Realtime's WebSocket transport for certificate pinning"
    )
  }

  @Test
  func userProvidedRealtimeSessionIsNotOverridden() {
    let localStorage = AuthLocalStorageMock()
    let globalSession = URLSession(configuration: .ephemeral)
    let realtimeSpecificSession = URLSession(configuration: .default)
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: globalSession),
        realtime: RealtimeClientOptions(session: realtimeSpecificSession)
      )
    )

    #expect(
      client.realtimeV2.options.session === realtimeSpecificSession,
      "user-provided realtime session should be preserved"
    )
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SupabaseClientTests`
Expected: FAIL — `globalSessionPropagatedToRealtimeWebSocket` fails because `client.realtimeV2.options.session` is still `URLSession.shared`, not `customSession`.

- [ ] **Step 3: Wire the propagation**

In `Sources/Supabase/SupabaseClient.swift`, inside `_initRealtimeClient()`, add right after the existing `fetch` block (currently lines 496-500):

```swift
    if realtimeOptions.fetch == nil {
      realtimeOptions.fetch = { [session = options.global.session] request in
        try await session.data(for: TraceContext.inject(into: request))
      }
    }

    if realtimeOptions.session === URLSession.shared {
      realtimeOptions.session = options.global.session
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SupabaseClientTests`
Expected: PASS (all tests, including the two new ones)

- [ ] **Step 5: Commit**

```bash
./scripts/format.sh
git add Sources/Supabase/SupabaseClient.swift Tests/SupabaseTests/SupabaseClientTests.swift
git commit -m "feat(supabase): propagate global.session to Realtime for WebSocket cert pinning"
```

---

### Task 6: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Format**

Run: `./scripts/format.sh`
Expected: no diffs after running (already formatted incrementally per task; this is a final sweep).

- [ ] **Step 2: Full build**

Run: `swift build`
Expected: builds with no errors or warnings.

- [ ] **Step 3: Full test suite**

Run: `swift test`
Expected: all tests PASS, including `RealtimeClientOptionsTests`, `WebSocketTests`, `SupabaseClientTests`.

- [ ] **Step 4: Spell check**

Run: `npm ci --prefix tools/node && ./scripts/spell-check.sh`
Expected: no new unknown-word errors. Likely candidates needing a `dictionary.txt` entry: `openssl`, `pkcs12` (from Task 3's cert-generation shell commands/comments). Add any flagged word there.

- [ ] **Step 5: DocC build**

Run: `./scripts/test-docs.sh`
Expected: no warnings — specifically confirms the updated `RealtimeClientOptions` init DocC symbol reference (Task 1) resolves correctly and no non-public symbol (`session`) is referenced from a public Topics list.

- [ ] **Step 6: Manual sanity check of the `Usage` example from PR #1117's motivation**

Confirm the following compiles as a smoke test (add temporarily to a scratch file or a REPL, not committed) — this is the shape an app would actually use:

```swift
final class PinningDelegate: NSObject, URLSessionDelegate {
  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    // pinning logic
    completionHandler(.performDefaultHandling, nil)
  }
}

let pinnedSession = URLSession(
  configuration: .default, delegate: PinningDelegate(), delegateQueue: nil)

let client = SupabaseClient(
  supabaseURL: URL(string: "https://project-ref.supabase.co")!,
  supabaseKey: "PUBLISHABLE_KEY",
  options: SupabaseClientOptions(global: .init(session: pinnedSession))
)
// `client.realtimeV2`'s WebSocket connection now forwards auth challenges to `PinningDelegate`.
```

Expected: compiles without errors; no changes needed to Storage/Auth/PostgREST call sites (they already used `global.session`).
