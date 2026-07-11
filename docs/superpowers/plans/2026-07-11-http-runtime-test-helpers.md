# HTTPRuntimeTestHelpers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `HTTPRuntimeTestHelpers` SPM target providing first-party Swift Testing support for stubbing `HTTPTransport`-issued requests (`.http(stubs:)` trait) and asserting the shape of outgoing requests (`assertHTTPRequests`).

**Architecture:** A `HTTPTransportStub` actor conforms to `HTTPTransport` and holds an ordered, consume-once stub queue plus a log of every request it has seen. A `TestScoping` trait (`.http(stubs:)`) binds it to a `@TaskLocal` for the duration of a test — isolated per task tree, so parallel `swift test` runs never share state. Tests read `HTTPTransportStub.current` and pass it explicitly to the client under test (constructor injection, same as production code). `assertHTTPRequests` wraps an operation and asserts an inline curl snapshot of whatever requests it made, read back from the same transport.

**Tech Stack:** Swift 6.1, Swift Testing (`Testing`), `InlineSnapshotTesting` (already a repo dependency via `swift-snapshot-testing`), the existing `HTTPRuntime` target.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-11-http-runtime-test-helpers-design.md` — read it before starting; this plan implements it exactly.
- Every declaration in `HTTPRuntimeTestHelpers` is `package`-scoped, never `public` — this target is test support, not shipped API, and stray `public` symbols trip the repo's "Check public API against capability matrix" CI job (this bit HTTPRuntime once already; see `Sources/HTTPRuntime/TransferProgress.swift` history).
- No dependency on `Sources/TestHelpers` — `HTTPRuntime` and its test helpers are deliberately low-dependency, standalone targets.
- Not a wrapper around `Replay` — `HTTPTransportStub` mocks at the `HTTPTransport` protocol level, independent of `Replay`'s `URLSession`-fetch-closure mocking used by Auth/PostgREST/Functions.
- Run `./scripts/format.sh` before every commit in this plan (swift-format). Run `./scripts/spell-check.sh` before the final commit and add any flagged word to `dictionary.txt` under a new "Terms from HTTPRuntimeTestHelpers" section.
- Test files: Swift Testing only (`@Suite`, `@Test`, `#expect`), test function names drop the `test` prefix, per `AGENTS.md`.
- File headers follow the existing convention: `//\n//  FileName.swift\n//  ModuleName\n//\n//  Created by Guilherme Souza on 11/07/26.\n//`.

---

## File Structure

- `Package.swift` — add `HTTPRuntimeTestHelpers` target + `HTTPRuntimeTestHelpersTests` test target.
- `Sources/HTTPRuntimeTestHelpers/HTTPStubBody.swift` — the `HTTPStubBody` enum (canned response body shapes).
- `Sources/HTTPRuntimeTestHelpers/HTTPStub.swift` — the `HTTPStub` struct + one static factory per HTTP verb.
- `Sources/HTTPRuntimeTestHelpers/HTTPTransportStub.swift` — `HTTPStubMismatch` error, the `HTTPTransportStub` actor (queue/match/consume/leftover/`current`), the `HTTPStubTrait` type, and the `http(stubs:)` free function. These last two live in this file (not their own) because `HTTPStubTrait.provideScope` needs `fileprivate` access to `HTTPTransportStub`'s `_current` TaskLocal and `remainingStubs`.
- `Sources/HTTPRuntimeTestHelpers/CurlCommand.swift` — `curlCommand(for:)`, rendering an `HTTPRequest` as a curl command.
- `Sources/HTTPRuntimeTestHelpers/AssertHTTPRequests.swift` — the `assertHTTPRequests` function.
- `Tests/HTTPRuntimeTestHelpersTests/HTTPStubTests.swift`
- `Tests/HTTPRuntimeTestHelpersTests/HTTPTransportStubTests.swift`
- `Tests/HTTPRuntimeTestHelpersTests/CurlCommandTests.swift`
- `Tests/HTTPRuntimeTestHelpersTests/HTTPStubTraitTests.swift`
- `Tests/HTTPRuntimeTestHelpersTests/AssertHTTPRequestsTests.swift`
- `Supabase.xcworkspace/xcshareddata/xcschemes/Supabase.xcscheme` — register `HTTPRuntimeTestHelpersTests`.
- `dictionary.txt` — any new cspell-flagged words.

---

### Task 1: Scaffold the target + `HTTPStubBody`/`HTTPStub`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/HTTPRuntimeTestHelpers/HTTPStubBody.swift`
- Create: `Sources/HTTPRuntimeTestHelpers/HTTPStub.swift`
- Test: `Tests/HTTPRuntimeTestHelpersTests/HTTPStubTests.swift`

**Interfaces:**
- Produces: `HTTPStubBody` (`.empty`, `.string(String)`, `.data(Data)`, `.stream(AsyncStream<Data>)`); `HTTPStub` with `package let method: HTTPMethod`, `url: String`, `status: Int`, `headers: [String: String]`, `body: @Sendable () -> HTTPStubBody`, and static factories `.get`/`.post`/`.put`/`.patch`/`.delete`/`.head(_:status:headers:body:)`.

- [ ] **Step 1: Add the two new targets to `Package.swift`**

Find this block (the existing `HTTPRuntime`/`HTTPRuntimeTests` target pair):

```swift
    .target(
      name: "HTTPRuntime"
    ),
    .testTarget(
      name: "HTTPRuntimeTests",
      dependencies: [
        "HTTPRuntime"
      ]
    ),
```

Replace it with:

```swift
    .target(
      name: "HTTPRuntime"
    ),
    .testTarget(
      name: "HTTPRuntimeTests",
      dependencies: [
        "HTTPRuntime"
      ]
    ),
    .target(
      name: "HTTPRuntimeTestHelpers",
      dependencies: [
        "HTTPRuntime",
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
      ]
    ),
    .testTarget(
      name: "HTTPRuntimeTestHelpersTests",
      dependencies: [
        "HTTPRuntimeTestHelpers"
      ]
    ),
```

Then find:

```swift
let swift6TestTargets: Set<String> = ["SupabaseTests", "HelpersTests", "HTTPRuntimeTests"]
```

Replace it with:

```swift
let swift6TestTargets: Set<String> = [
  "SupabaseTests", "HelpersTests", "HTTPRuntimeTests", "HTTPRuntimeTestHelpersTests",
]
```

- [ ] **Step 2: Write `HTTPStubBody`**

Create `Sources/HTTPRuntimeTestHelpers/HTTPStubBody.swift`:

```swift
//
//  HTTPStubBody.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation

/// The canned response body for an ``HTTPStub``.
package enum HTTPStubBody: Sendable {
  case empty
  case string(String)
  case data(Data)
  /// Chunks delivered over time — for stubbing `HTTPTransport.stream()`.
  case stream(AsyncStream<Data>)
}
```

- [ ] **Step 3: Write `HTTPStub`**

Create `Sources/HTTPRuntimeTestHelpers/HTTPStub.swift`:

```swift
//
//  HTTPStub.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import HTTPRuntime

/// A canned response for one request, matched by HTTP method + full URL
/// (including query), consumed in the order it appears in `.http(stubs:)`'s
/// array. Only ever describes the *response* — see `assertHTTPRequests` to
/// assert the shape of the outgoing request.
package struct HTTPStub: Sendable {
  package let method: HTTPMethod
  package let url: String
  package let status: Int
  package let headers: [String: String]
  package let body: @Sendable () -> HTTPStubBody

  private init(
    method: HTTPMethod, url: String, status: Int, headers: [String: String],
    body: @escaping @Sendable () -> HTTPStubBody
  ) {
    self.method = method
    self.url = url
    self.status = status
    self.headers = headers
    self.body = body
  }

  package static func get(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .get, url: url, status: status, headers: headers, body: body)
  }

  package static func post(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .post, url: url, status: status, headers: headers, body: body)
  }

  package static func put(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .put, url: url, status: status, headers: headers, body: body)
  }

  package static func patch(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .patch, url: url, status: status, headers: headers, body: body)
  }

  package static func delete(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .delete, url: url, status: status, headers: headers, body: body)
  }

  package static func head(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .head, url: url, status: status, headers: headers, body: body)
  }
}
```

- [ ] **Step 4: Write the failing test**

Create `Tests/HTTPRuntimeTestHelpersTests/HTTPStubTests.swift`:

```swift
//
//  HTTPStubTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Testing

@testable import HTTPRuntimeTestHelpers

@Suite
struct HTTPStubTests {
  @Test
  func getBuildsExpectedStub() {
    let stub = HTTPStub.get("https://example.com/x", status: 201, headers: ["X-Test": "1"]) {
      .string("hello")
    }
    #expect(stub.method == .get)
    #expect(stub.url == "https://example.com/x")
    #expect(stub.status == 201)
    #expect(stub.headers == ["X-Test": "1"])
    guard case .string(let value) = stub.body() else {
      Issue.record("expected .string body")
      return
    }
    #expect(value == "hello")
  }

  @Test
  func defaultsToStatus200AndEmptyBody() {
    let stub = HTTPStub.post("https://example.com/y")
    #expect(stub.status == 200)
    #expect(stub.headers.isEmpty)
    guard case .empty = stub.body() else {
      Issue.record("expected .empty body")
      return
    }
  }

  @Test
  func everyVerbFactoryProducesItsMethod() {
    #expect(HTTPStub.get("https://example.com").method == .get)
    #expect(HTTPStub.post("https://example.com").method == .post)
    #expect(HTTPStub.put("https://example.com").method == .put)
    #expect(HTTPStub.patch("https://example.com").method == .patch)
    #expect(HTTPStub.delete("https://example.com").method == .delete)
    #expect(HTTPStub.head("https://example.com").method == .head)
  }
}
```

This step is written after Steps 1–3 (unlike the canonical write-test-first order) because `Package.swift` needs both the target and at least one source file to exist before `swift build`/`swift test` can even resolve the new module — there is no meaningful "compile-fails" checkpoint before that scaffolding exists.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter HTTPRuntimeTestHelpersTests`
Expected: `Test run with 3 tests in 1 suite passed` (or similar — 3 tests, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/HTTPRuntimeTestHelpers/HTTPStubBody.swift Sources/HTTPRuntimeTestHelpers/HTTPStub.swift Tests/HTTPRuntimeTestHelpersTests/HTTPStubTests.swift
git commit -m "feat(runtime): scaffold HTTPRuntimeTestHelpers, add HTTPStubBody/HTTPStub"
```

---

### Task 2: `HTTPTransportStub` — the ordered, consume-once stub queue

**Files:**
- Create: `Sources/HTTPRuntimeTestHelpers/HTTPTransportStub.swift`
- Test: `Tests/HTTPRuntimeTestHelpersTests/HTTPTransportStubTests.swift`

**Interfaces:**
- Consumes: `HTTPStub` (Task 1) — `method`, `url`, `status`, `headers`, `body: @Sendable () -> HTTPStubBody`. `HTTPTransport` protocol from `HTTPRuntime` (`send(_:uploadProgress:)`, `stream(_:)`, both `async throws(HTTPError)`). `HTTPRequest`, `HTTPResponse`, `HTTPResponseHead`, `HTTPResponseStream`, `HTTPError.transport(any Error)`, `ProgressHandler` from `HTTPRuntime`.
- Produces: `package actor HTTPTransportStub: HTTPTransport` with `package init(stubs: [HTTPStub])`, `package static var current: HTTPTransportStub`, `package func assertAllConsumed()`, `package var requestCount: Int`, `package func requests(since index: Int) -> [HTTPRequest]`. Also a `fileprivate` TaskLocal `_current` and `fileprivate var remainingStubs: [HTTPStub]` — both consumed by Task 4's `HTTPStubTrait`, which is appended to this same file.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HTTPRuntimeTestHelpersTests/HTTPTransportStubTests.swift`:

```swift
//
//  HTTPTransportStubTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import Testing

@testable import HTTPRuntimeTestHelpers
import HTTPRuntime

@Suite
struct HTTPTransportStubTests {
  @Test
  func matchesAndReturnsStubbedResponse() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a", status: 201, headers: ["X": "1"]) { .string("hi") }
    ])
    let response = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), uploadProgress: nil)
    #expect(response.head.status == 201)
    #expect(response.head.headers == ["X": "1"])
    #expect(response.body == Data("hi".utf8))
  }

  @Test
  func consumesStubsInOrder() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a") { .string("first") },
      .get("https://example.com/b") { .string("second") },
    ])
    let first = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), uploadProgress: nil)
    let second = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/b")!), uploadProgress: nil)
    #expect(first.body == Data("first".utf8))
    #expect(second.body == Data("second".utf8))
  }

  @Test
  func mismatchRecordsIssueAndThrows() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/expected") { .empty }
    ])
    await withKnownIssue {
      _ = try await transport.send(
        HTTPRequest(method: .post, url: URL(string: "https://example.com/actual")!), uploadProgress: nil)
    }
  }

  @Test
  func exhaustedQueueRecordsIssueAndThrows() async throws {
    let transport = HTTPTransportStub(stubs: [])
    await withKnownIssue {
      _ = try await transport.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), uploadProgress: nil)
    }
  }

  @Test
  func assertAllConsumedRecordsIssueForLeftoverStubs() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/never-called") { .empty }
    ])
    await withKnownIssue {
      await transport.assertAllConsumed()
    }
  }

  @Test
  func currentOutsideScopeRecordsIssueAndReturnsUsableTransport() async throws {
    await withKnownIssue {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), uploadProgress: nil)
    }
  }

  @Test
  func streamYieldsStubbedChunks() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a") { .data(Data("chunk".utf8)) }
    ])
    let responseStream = try await transport.stream(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!))
    var collected = Data()
    for try await chunk in responseStream.body { collected.append(chunk) }
    #expect(collected == Data("chunk".utf8))
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.HTTPTransportStubTests`
Expected: FAIL — `cannot find 'HTTPTransportStub' in scope` (the type doesn't exist yet).

- [ ] **Step 3: Implement `HTTPTransportStub`**

Create `Sources/HTTPRuntimeTestHelpers/HTTPTransportStub.swift`:

```swift
//
//  HTTPTransportStub.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import HTTPRuntime
import Testing

/// Thrown into `HTTPError.transport` on a stub mismatch — the actual test
/// failure is the `Issue.record` call alongside it; this just gives the code
/// under test a real error to handle if it inspects the failure.
package struct HTTPStubMismatch: Error, CustomStringConvertible {
  package let description: String
}

/// The `HTTPTransport` backing `.http(stubs:)` — an ordered, consume-once
/// stub queue. Bound to the current task tree via `HTTPStubTrait` (below).
package actor HTTPTransportStub: HTTPTransport {
  @TaskLocal fileprivate static var _current: HTTPTransportStub?

  /// The stub transport bound by the enclosing `.http(stubs:)` trait scope.
  /// Outside such a scope, accessing this records an issue and returns an
  /// empty-queue instance — any request against it fails through the normal
  /// "no stubs remaining" path below rather than crashing.
  package static var current: HTTPTransportStub {
    guard let value = _current else {
      Issue.record("HTTPTransportStub.current accessed outside a .http trait scope")
      return HTTPTransportStub(stubs: [])
    }
    return value
  }

  private var pending: [HTTPStub]
  private var consumedRequests: [HTTPRequest] = []

  package init(stubs: [HTTPStub]) {
    pending = stubs
  }

  private func nextMatchingStub(for request: HTTPRequest) throws(HTTPError) -> HTTPStub {
    consumedRequests.append(request)
    guard !pending.isEmpty else {
      let message =
        "Unexpected request \(request.method.rawValue) \(request.url.absoluteString) — no stubs remaining"
      Issue.record("\(message)")
      throw HTTPError.transport(HTTPStubMismatch(description: message))
    }
    let stub = pending.removeFirst()
    guard stub.method == request.method, stub.url == request.url.absoluteString else {
      let message = """
        Request mismatch.
        Expected: \(stub.method.rawValue) \(stub.url)
        Actual:   \(request.method.rawValue) \(request.url.absoluteString)
        """
      Issue.record("\(message)")
      throw HTTPError.transport(HTTPStubMismatch(description: message))
    }
    return stub
  }

  package func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?) async throws(HTTPError)
    -> HTTPResponse
  {
    let stub = try nextMatchingStub(for: request)
    let bodyData: Data
    switch stub.body() {
    case .empty:
      bodyData = Data()
    case .string(let value):
      bodyData = Data(value.utf8)
    case .data(let value):
      bodyData = value
    case .stream(let stream):
      var collected = Data()
      for await chunk in stream { collected.append(chunk) }
      bodyData = collected
    }
    return HTTPResponse(head: HTTPResponseHead(status: stub.status, headers: stub.headers), body: bodyData)
  }

  package func stream(_ request: HTTPRequest) async throws(HTTPError) -> HTTPResponseStream {
    let stub = try nextMatchingStub(for: request)
    let responseBody: AsyncThrowingStream<Data, any Error>
    switch stub.body() {
    case .empty:
      responseBody = AsyncThrowingStream { $0.finish() }
    case .string(let value):
      responseBody = AsyncThrowingStream { continuation in
        continuation.yield(Data(value.utf8))
        continuation.finish()
      }
    case .data(let value):
      responseBody = AsyncThrowingStream { continuation in
        continuation.yield(value)
        continuation.finish()
      }
    case .stream(let stream):
      responseBody = AsyncThrowingStream { continuation in
        let task = Task {
          for await chunk in stream { continuation.yield(chunk) }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
    return HTTPResponseStream(
      head: HTTPResponseHead(status: stub.status, headers: stub.headers), body: responseBody)
  }

  /// Records an issue for every stub that was never consumed. Called by
  /// `HTTPStubTrait` at scope exit.
  package func assertAllConsumed() {
    for stub in pending {
      Issue.record("Stub for \(stub.method.rawValue) \(stub.url) was never consumed")
    }
  }

  /// Count of requests recorded so far — `assertHTTPRequests` snapshots this
  /// before running its operation, then diffs against it after.
  package var requestCount: Int { consumedRequests.count }

  /// Requests recorded from `index` onward.
  package func requests(since index: Int) -> [HTTPRequest] { Array(consumedRequests[index...]) }

  /// Stubs not yet consumed — read by `HTTPStubTrait` (below) to merge a
  /// suite-level queue with a nested test-level one.
  fileprivate var remainingStubs: [HTTPStub] { pending }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.HTTPTransportStubTests`
Expected: `Test run with 7 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/HTTPRuntimeTestHelpers/HTTPTransportStub.swift Tests/HTTPRuntimeTestHelpersTests/HTTPTransportStubTests.swift
git commit -m "feat(runtime): add HTTPTransportStub, the consume-once stub queue"
```

---

### Task 3: `curlCommand(for:)`

**Files:**
- Create: `Sources/HTTPRuntimeTestHelpers/CurlCommand.swift`
- Test: `Tests/HTTPRuntimeTestHelpersTests/CurlCommandTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest` (`method: HTTPMethod`, `url: URL`, `headers: [String: String]`, `body: HTTPBody?`) from `HTTPRuntime`.
- Produces: `package func curlCommand(for request: HTTPRequest) -> String`, used by Task 5's `assertHTTPRequests`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HTTPRuntimeTestHelpersTests/CurlCommandTests.swift`:

```swift
//
//  CurlCommandTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import Testing

@testable import HTTPRuntimeTestHelpers
import HTTPRuntime

@Suite
struct CurlCommandTests {
  @Test
  func rendersGetWithSortedHeadersAndQuery() {
    let request = HTTPRequest(
      method: .get,
      url: URL(string: "https://example.com/x?b=2&a=1")!,
      headers: ["Content-Type": "application/json", "Accept": "application/json"])
    #expect(
      curlCommand(for: request) == """
        curl \\
        \t--header "Accept: application/json" \\
        \t--header "Content-Type: application/json" \\
        \t"https://example.com/x?a=1&b=2"
        """)
  }

  @Test
  func rendersPostWithEscapedBody() {
    let request = HTTPRequest(
      method: .post,
      url: URL(string: "https://example.com/x")!,
      headers: [:],
      body: .data(Data(#"{"a":1}"#.utf8)))
    #expect(
      curlCommand(for: request) == #"""
        curl \
        	--request POST \
        	--data "{\"a\":1}" \
        	"https://example.com/x"
        """#)
  }

  @Test
  func rendersHead() {
    let request = HTTPRequest(method: .head, url: URL(string: "https://example.com/x")!)
    #expect(
      curlCommand(for: request) == """
        curl \\
        \t--head \\
        \t"https://example.com/x"
        """)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.CurlCommandTests`
Expected: FAIL — `cannot find 'curlCommand' in scope`.

- [ ] **Step 3: Implement `curlCommand(for:)`**

Create `Sources/HTTPRuntimeTestHelpers/CurlCommand.swift`:

```swift
//
//  CurlCommand.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import HTTPRuntime

/// Renders an `HTTPRequest` as a curl command — method, sorted headers,
/// escaped body, sorted query items. Mirrors the conventions of
/// `Sources/TestHelpers/URLRequestSnapshot.swift`'s `._curl` strategy for
/// `URLRequest`, implemented independently against `HTTPRequest` so this
/// target has no dependency on `TestHelpers`. `.file` request bodies aren't
/// rendered (no `--data` line) — out of scope for this helper's JSON-body
/// use case.
package func curlCommand(for request: HTTPRequest) -> String {
  var components = ["curl"]

  switch request.method {
  case .get: break
  case .head: components.append("--head")
  default: components.append("--request \(request.method.rawValue)")
  }

  for field in request.headers.keys.sorted() where field != "Cookie" {
    let escapedValue = request.headers[field]!.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--header \"\(field): \(escapedValue)\"")
  }

  if case .data(let data) = request.body, let httpBody = String(data: data, encoding: .utf8) {
    var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
    escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--data \"\(escapedBody)\"")
  }

  if let cookie = request.headers["Cookie"] {
    let escapedValue = cookie.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--cookie \"\(escapedValue)\"")
  }

  components.append("\"\(sortedQueryURL(request.url).absoluteString)\"")

  return components.joined(separator: " \\\n\t")
}

private func sortedQueryURL(_ url: URL) -> URL {
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
    let queryItems = components.queryItems
  else {
    return url
  }
  components.queryItems = queryItems.sorted { $0.name < $1.name }
  return components.url ?? url
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.CurlCommandTests`
Expected: `Test run with 3 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/HTTPRuntimeTestHelpers/CurlCommand.swift Tests/HTTPRuntimeTestHelpersTests/CurlCommandTests.swift
git commit -m "feat(runtime): add curlCommand(for:) request formatter"
```

---

### Task 4: `HTTPStubTrait` + `http(stubs:)`

**Files:**
- Modify: `Sources/HTTPRuntimeTestHelpers/HTTPTransportStub.swift` (append to the end of the file)
- Test: `Tests/HTTPRuntimeTestHelpersTests/HTTPStubTraitTests.swift`

**Interfaces:**
- Consumes: `HTTPTransportStub` (Task 2) — its `fileprivate` `_current` TaskLocal, `init(stubs:)`, `remainingStubs`, `assertAllConsumed()`. `Testing.TestTrait`, `Testing.SuiteTrait`, `Testing.TestScoping`, `Testing.Test`, `Testing.Test.Case` from the `Testing` module.
- Produces: `package func http(stubs: [HTTPStub]) -> HTTPStubTrait`, usable as `@Test(.http(stubs: [...]))` or `@Suite(.http(stubs: [...]))`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HTTPRuntimeTestHelpersTests/HTTPStubTraitTests.swift`:

```swift
//
//  HTTPStubTraitTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import Testing

@testable import HTTPRuntimeTestHelpers
import HTTPRuntime

@Suite
struct HTTPStubTraitTests {
  @Test(.http(stubs: [.get("https://example.com/x", status: 200) { .string("ok") }]))
  func bindsCurrentForTestBody() async throws {
    let response = try await HTTPTransportStub.current.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), uploadProgress: nil)
    #expect(response.body == Data("ok".utf8))
  }

  @Test
  func leftoverStubRecordsIssueAtScopeExit() async throws {
    let trait = http(stubs: [.get("https://example.com/never-called") { .empty }])
    await withKnownIssue {
      try await trait.provideScope(for: Test.current!, testCase: Test.Case.current) {
        // Deliberately consume nothing.
      }
    }
  }

  @Test
  func suiteAndTestStubsMergeInOrder() async throws {
    let suiteLevelTrait = http(stubs: [.get("https://example.com/first") { .string("1") }])
    let testLevelTrait = http(stubs: [.get("https://example.com/second") { .string("2") }])
    try await suiteLevelTrait.provideScope(for: Test.current!, testCase: Test.Case.current) {
      try await testLevelTrait.provideScope(for: Test.current!, testCase: Test.Case.current) {
        let first = try await HTTPTransportStub.current.send(
          HTTPRequest(method: .get, url: URL(string: "https://example.com/first")!), uploadProgress: nil)
        let second = try await HTTPTransportStub.current.send(
          HTTPRequest(method: .get, url: URL(string: "https://example.com/second")!), uploadProgress: nil)
        #expect(first.body == Data("1".utf8))
        #expect(second.body == Data("2".utf8))
      }
    }
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.HTTPStubTraitTests`
Expected: FAIL — `type 'HTTPStubTrait' has no member 'http'` / `cannot infer contextual base in reference to member 'http'` (the trait and free function don't exist yet).

- [ ] **Step 3: Implement `HTTPStubTrait` + `http(stubs:)`**

Append to the end of `Sources/HTTPRuntimeTestHelpers/HTTPTransportStub.swift`:

```swift

/// Declares canned responses for `HTTPTransport`-issued requests made during
/// a test. Usable at `@Test` or `@Suite` level; a `@Test`-level trait appends
/// its stubs to whatever an enclosing `@Suite`-level trait already queued,
/// preserving order.
package struct HTTPStubTrait: TestTrait, SuiteTrait, TestScoping {
  package let isRecursive = true

  fileprivate let stubs: [HTTPStub]

  package func provideScope(
    for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
  ) async throws {
    let outerStubs = await HTTPTransportStub._current?.remainingStubs ?? []
    let transport = HTTPTransportStub(stubs: outerStubs + stubs)
    try await HTTPTransportStub.$_current.withValue(transport) {
      try await function()
      await transport.assertAllConsumed()
    }
  }
}

/// `@Test(.http(stubs: [.get("https://example.com/x") { .string("...") }]))`
package func http(stubs: [HTTPStub]) -> HTTPStubTrait {
  HTTPStubTrait(stubs: stubs)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.HTTPStubTraitTests`
Expected: `Test run with 3 tests in 1 suite passed`.

- [ ] **Step 5: Run the full HTTPRuntimeTestHelpersTests suite to check for regressions**

Run: `swift test --filter HTTPRuntimeTestHelpersTests`
Expected: all tests from Tasks 1–4 pass (13 tests total: 3 + 7 + 3, `HTTPStubTraitTests` not yet counted — actual total 16 across 4 suites).

- [ ] **Step 6: Commit**

```bash
git add Sources/HTTPRuntimeTestHelpers/HTTPTransportStub.swift Tests/HTTPRuntimeTestHelpersTests/HTTPStubTraitTests.swift
git commit -m "feat(runtime): add HTTPStubTrait and the .http(stubs:) trait"
```

---

### Task 5: `assertHTTPRequests`

**Files:**
- Create: `Sources/HTTPRuntimeTestHelpers/AssertHTTPRequests.swift`
- Test: `Tests/HTTPRuntimeTestHelpersTests/AssertHTTPRequestsTests.swift`

**Interfaces:**
- Consumes: `HTTPTransportStub.current`, `.requestCount`, `.requests(since:)` (Task 2); `curlCommand(for:)` (Task 3); `InlineSnapshotTesting.assertInlineSnapshot`, `Snapshotting<String, String>.lines`, `InlineSnapshotSyntaxDescriptor`.
- Produces: `package func assertHTTPRequests<R>(fileID:filePath:function:line:column:_:matches:) async throws -> R`, called as `try await assertHTTPRequests { operation } matches: { snapshot }`.

This task relies on `InlineSnapshotTesting`'s real recording behavior: when `matches:` is omitted, the **first** run intentionally fails (`"Automatically recorded a new snapshot. Re-run ... to assert against the newly-recorded snapshot."`) while rewriting the calling test file's source to insert the recorded literal; the **second** run then passes. This is the standard, documented way this library is used (already the pattern behind `assertSnapshot(of: request, as: .curl, ...)` elsewhere in this repo) — the steps below follow that two-run flow instead of the canonical single "write code, run once, pass" shape.

- [ ] **Step 1: Write the tests without a recorded snapshot yet**

Create `Tests/HTTPRuntimeTestHelpersTests/AssertHTTPRequestsTests.swift`:

```swift
//
//  AssertHTTPRequestsTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import Testing

@testable import HTTPRuntimeTestHelpers
import HTTPRuntime

@Suite
struct AssertHTTPRequestsTests {
  @Test(
    .http(stubs: [
      .get("https://example.com/a") { .empty },
      .get("https://example.com/b") { .empty },
      .get("https://example.com/c") { .empty },
    ]))
  func onlyCapturesRequestsMadeDuringItsOwnOperation() async throws {
    // Fires one request *before* any assertHTTPRequests call — must not leak
    // into the slice captured below.
    _ = try await HTTPTransportStub.current.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), uploadProgress: nil)

    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/b")!), uploadProgress: nil)
    }

    // A second call must only see requests made after the first one returned.
    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/c")!), uploadProgress: nil)
    }
  }

  @Test(
    .http(stubs: [
      .get("https://example.com/first") { .empty },
      .post("https://example.com/second") { .empty },
    ]))
  func rendersMultipleRequestsJoinedByBlankLine() async throws {
    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/first")!), uploadProgress: nil)
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .post, url: URL(string: "https://example.com/second")!), uploadProgress: nil)
    }
  }
}
```

Note both `assertHTTPRequests` calls are written **without** a `matches:` trailing closure — that's intentional, see the recording flow above.

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.AssertHTTPRequestsTests`
Expected: FAIL — `cannot find 'assertHTTPRequests' in scope`.

- [ ] **Step 3: Implement `assertHTTPRequests`**

Create `Sources/HTTPRuntimeTestHelpers/AssertHTTPRequests.swift`:

```swift
//
//  AssertHTTPRequests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
@preconcurrency import InlineSnapshotTesting
import HTTPRuntime

/// Runs `operation`, then asserts an inline curl snapshot of every request
/// `operation` made against the ambient `HTTPTransportStub.current` — i.e.
/// this must run inside a `.http(stubs:)` scope. Multiple requests made
/// during `operation` render as multiple curl commands joined by a blank
/// line, in call order.
package func assertHTTPRequests<R>(
  fileID: StaticString = #fileID, filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line, column: UInt = #column,
  _ operation: () async throws -> R,
  matches expected: (() -> String)? = nil
) async throws -> R {
  let transport = HTTPTransportStub.current
  let startIndex = await transport.requestCount
  let result = try await operation()
  let requests = await transport.requests(since: startIndex)
  let rendered = requests.map(curlCommand(for:)).joined(separator: "\n\n")
  assertInlineSnapshot(
    of: rendered, as: .lines,
    syntaxDescriptor: InlineSnapshotSyntaxDescriptor(trailingClosureOffset: 1),
    matches: expected,
    fileID: fileID, file: filePath, function: function, line: line, column: column)
  return result
}
```

- [ ] **Step 4: Run the tests once to auto-record the snapshots**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.AssertHTTPRequestsTests`
Expected: FAIL, with messages containing `"Automatically recorded a new snapshot. Re-run ... to assert against the newly-recorded snapshot."` — one per `assertHTTPRequests` call (3 total: 2 in the first test, 1 in the second). This run also rewrites `Tests/HTTPRuntimeTestHelpersTests/AssertHTTPRequestsTests.swift` in place, inserting a `matches: { ... }` trailing closure at each call site with the recorded curl text.

- [ ] **Step 5: Inspect the recorded snapshots**

Run: `git diff Tests/HTTPRuntimeTestHelpersTests/AssertHTTPRequestsTests.swift`
Expected: each `assertHTTPRequests { ... }` call now has an inserted `matches: { """ curl ... """ }` trailing closure. Confirm:
- The first test's first snapshot renders only `https://example.com/b` (not `/a`).
- The first test's second snapshot renders only `https://example.com/c` (not `/a` or `/b`).
- The second test's snapshot renders two curl blocks (`/first` then `--request POST .../second`) separated by a blank line.

If any of these don't hold, the implementation in Step 3 has a bug — fix it and repeat from Step 4. Do not hand-edit the recorded snapshot text.

- [ ] **Step 6: Run the tests again to verify they now pass**

Run: `swift test --filter HTTPRuntimeTestHelpersTests.AssertHTTPRequestsTests`
Expected: `Test run with 2 tests in 1 suite passed`.

- [ ] **Step 7: Commit**

```bash
git add Sources/HTTPRuntimeTestHelpers/AssertHTTPRequests.swift Tests/HTTPRuntimeTestHelpersTests/AssertHTTPRequestsTests.swift
git commit -m "feat(runtime): add assertHTTPRequests for request-shape assertions"
```

---

### Task 6: Xcode scheme, spell-check, and final verification

**Files:**
- Modify: `Supabase.xcworkspace/xcshareddata/xcschemes/Supabase.xcscheme`
- Modify: `dictionary.txt` (only if spell-check flags new words)

**Interfaces:** None — this task wires up tooling around the code from Tasks 1–5, it doesn't add new symbols.

- [ ] **Step 1: Register `HTTPRuntimeTestHelpersTests` in the shared Xcode scheme**

In `Supabase.xcworkspace/xcshareddata/xcschemes/Supabase.xcscheme`, find this block (inside the `<TestAction>` → `<Testables>` section, right after `HelpersTests` and right before `HTTPRuntimeTests`):

```xml
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "HelpersTests"
               BuildableName = "HelpersTests"
               BlueprintName = "HelpersTests"
               ReferencedContainer = "container:">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "HTTPRuntimeTests"
               BuildableName = "HTTPRuntimeTests"
               BlueprintName = "HTTPRuntimeTests"
               ReferencedContainer = "container:">
            </BuildableReference>
         </TestableReference>
```

Insert a new `TestableReference` for `HTTPRuntimeTestHelpersTests` between them (alphabetical order: `HelpersTests` < `HTTPRuntimeTestHelpersTests` < `HTTPRuntimeTests`), so the block becomes:

```xml
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "HelpersTests"
               BuildableName = "HelpersTests"
               BlueprintName = "HelpersTests"
               ReferencedContainer = "container:">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "HTTPRuntimeTestHelpersTests"
               BuildableName = "HTTPRuntimeTestHelpersTests"
               BlueprintName = "HTTPRuntimeTestHelpersTests"
               ReferencedContainer = "container:">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "HTTPRuntimeTests"
               BuildableName = "HTTPRuntimeTests"
               BlueprintName = "HTTPRuntimeTests"
               ReferencedContainer = "container:">
            </BuildableReference>
         </TestableReference>
```

- [ ] **Step 2: Confirm no `public` declarations leaked into the new target**

Run: `grep -rn "^public\| public " Sources/HTTPRuntimeTestHelpers/`
Expected: no output (every declaration is `package`).

- [ ] **Step 3: Run the full test suite for both new targets**

Run: `swift test --filter HTTPRuntimeTestHelpersTests`
Expected: all tests across `HTTPStubTests`, `HTTPTransportStubTests`, `CurlCommandTests`, `HTTPStubTraitTests`, `AssertHTTPRequestsTests` pass (18 tests total: 3 + 7 + 3 + 3 + 2, across 5 suites).
Also run: `swift build`
Expected: builds cleanly with no warnings from the new target.

- [ ] **Step 4: Format**

Run: `./scripts/format.sh`
Expected: exits 0. If it reformats any file in `Sources/HTTPRuntimeTestHelpers/` or `Tests/HTTPRuntimeTestHelpersTests/`, review the diff (should be whitespace-only) and keep it.

- [ ] **Step 5: Spell-check**

Run: `npm ci --prefix tools/node` (only if `tools/node/package-lock.json` changed since last run — otherwise skip), then `./scripts/spell-check.sh`
Expected: exits 0. If it flags a word introduced by this plan (e.g. an identifier fragment cspell doesn't recognize), add it to `dictionary.txt` under a new section:

```
# Terms from HTTPRuntimeTestHelpers (Sources/HTTPRuntimeTestHelpers) and its tests.
<flagged words here, one per line, alphabetized within the section>
```

Re-run `./scripts/spell-check.sh` until it exits 0.

- [ ] **Step 6: Commit**

```bash
git add Supabase.xcworkspace/xcshareddata/xcschemes/Supabase.xcscheme dictionary.txt
git commit -m "chore(ci): register HTTPRuntimeTestHelpersTests in the Supabase scheme and dictionary"
```

If Step 5 didn't touch `dictionary.txt`, drop it from the `git add`/commit — don't commit a no-op change to that file.
