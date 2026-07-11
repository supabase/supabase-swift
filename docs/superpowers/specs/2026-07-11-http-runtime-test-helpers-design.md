# HTTPRuntimeTestHelpers design

## Goal

First-party Swift Testing support for stubbing `HTTPTransport`-issued requests: a
custom trait (`.http(stubs:)`) that lets a test declare expected requests and
canned responses, works under parallel test execution, and asserts both the
response contract and (optionally) the shape of the outgoing request.

## Non-goals

- Not a wrapper around [Replay](https://github.com/mattt/Replay). Replay mocks
  at the `URLSession`-fetch-closure level for Auth/PostgREST/Functions; this
  target mocks at the `HTTPTransport` protocol level and is independent.
- Not a general-purpose HTTP mocking library for use outside this repo's
  `HTTPRuntime`-based clients.

## Target

New SPM target `HTTPRuntimeTestHelpers` (test-support, not shipped to
consumers), depending on `HTTPRuntime`, `Testing`, and `InlineSnapshotTesting`.
Deliberately does **not** depend on the app-level `Sources/TestHelpers` target
— `HTTPRuntime` is a standalone, low-dependency package, and its test helpers
should mirror that.

## Components

### `HTTPStubBody`

```swift
public enum HTTPStubBody: Sendable {
  case empty
  case string(String)
  case data(Data)
  case stream(AsyncStream<Data>)   // for stubbing HTTPTransport.stream()
}
```

### `HTTPStub`

One static factory method per HTTP verb (`.get`, `.post`, `.put`, `.patch`,
`.delete`, `.head`). Matches the existing codebase convention of static
factories over a single parameterized initializer.

```swift
public struct HTTPStub: Sendable {
  public static func post(
    _ url: String,
    status: Int = 200,
    headers: [String: String] = [:],
    fileID: StaticString = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column,
    matches requestSnapshot: (() -> String)? = nil,
    body: @Sendable @escaping () -> HTTPStubBody = { .empty }
  ) -> HTTPStub
  // .get, .put, .patch, .delete, .head — same shape
}
```

- `url` is compared against the full outgoing URL string, including query,
  exactly (no path-only or pattern matching).
- `matches:` is opt-in (default `nil`). When present, it's wired into
  `assertInlineSnapshot(of:as:matches:)` against a curl-command rendering of
  the actual outgoing `HTTPRequest`, using the stub's captured
  `fileID`/`filePath`/`line`/`column` so the inline literal updates at the
  right source location under `--record`.

### `HTTPTransportStub`

The `HTTPTransport` conformance that backs the trait. An ordered,
consume-once queue: each call to `send`/`stream` pops the **next** stub (not a
search across all remaining stubs) and compares method + full URL. A mismatch
still consumes that slot — later calls will cascade into further mismatches,
which is intentional; the first recorded issue is the actionable one.

```swift
/// Thrown into `HTTPError.transport` on a stub mismatch — the actual test
/// failure is the `Issue.record` call alongside it, this just gives the code
/// under test a real error to handle if it inspects the failure.
struct HTTPStubMismatch: Error, CustomStringConvertible {
  let description: String
}

package actor HTTPTransportStub: HTTPTransport {
  @TaskLocal private static var _current: HTTPTransportStub?

  package static var current: HTTPTransportStub {
    guard let value = _current else {
      Issue.record("HTTPTransportStub.current accessed outside a .http trait scope")
      return HTTPTransportStub(stubs: [])
    }
    return value
  }

  private var pending: [HTTPStub]
  init(stubs: [HTTPStub]) { pending = stubs }

  func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?) async throws(HTTPError) -> HTTPResponse {
    guard !pending.isEmpty else {
      let message = "Unexpected request \(request.method) \(request.url) — no stubs remaining"
      Issue.record("\(message)")
      throw HTTPError.transport(HTTPStubMismatch(description: message))
    }
    let stub = pending.removeFirst()
    guard stub.method == request.method, stub.url == request.url.absoluteString else {
      let message = """
        Request mismatch.
        Expected: \(stub.method) \(stub.url)
        Actual:   \(request.method) \(request.url)
        """
      Issue.record("\(message)")
      throw HTTPError.transport(HTTPStubMismatch(description: message))
    }
    if let requestSnapshot = stub.requestSnapshot {
      assertInlineSnapshot(
        of: request, as: .curl, matches: requestSnapshot,
        fileID: stub.fileID, file: stub.filePath, line: stub.line, column: stub.column)
    }
    return HTTPResponse(head: HTTPResponseHead(status: stub.status, headers: stub.headers), body: stub.bodyData)
  }

  func stream(_ request: HTTPRequest) async throws(HTTPError) -> HTTPResponseStream {
    // same pop/compare/snapshot logic as send, yields .stream(AsyncStream<Data>) chunks
  }

  func assertAllConsumed() {
    for stub in pending {
      Issue.record("Stub for \(stub.method) \(stub.url) was never consumed")
    }
  }
}
```

`current` is always non-optional. Outside a `.http` scope, accessing it
records an issue immediately (via `Issue.record`) and hands back an
empty-queue instance — any subsequent request against it fails through the
normal "no stubs remaining" path rather than crashing.

### `Snapshotting<HTTPRequest, String>.curl`

New, independent strategy operating directly on `HTTPRequest` (method, url,
headers, body) — not bridged through `URLRequest`. Mirrors the formatting
conventions (sorted headers/query, escaped body) of the existing
`Sources/TestHelpers/URLRequestSnapshot.swift` `._curl` strategy for
consistency across the codebase's curl-snapshot output, but implemented
independently so `HTTPRuntimeTestHelpers` has no dependency on `TestHelpers`.

### `HTTPStubTrait`

Usable at both `@Test` and `@Suite` level. Suite-level stubs are prepended;
a `@Test`-level trait on top appends its own stubs to whatever the suite
already queued, preserving order.

```swift
public struct HTTPStubTrait: TestTrait, SuiteTrait, TestScoping {
  let stubs: [HTTPStub]

  public func provideScope(
    for test: Test, testCase: Test.Case?, performing function: () async throws -> Void
  ) async throws {
    let merged = (HTTPTransportStub._current?.pending ?? []) + stubs
    let transport = HTTPTransportStub(stubs: merged)
    try await HTTPTransportStub.$_current.withValue(transport) {
      try await function()
      transport.assertAllConsumed()
    }
  }
}

public func http(stubs: [HTTPStub]) -> HTTPStubTrait { .init(stubs: stubs) }
```

`TestScoping.provideScope` binds the TaskLocal for the duration of the test
body — isolated per task tree, so parallel Swift Testing runs never share
stub state across tests.

## Data flow

1. Test declares `@Test(.http(stubs: [...]))`.
2. Trait's `provideScope` builds an `HTTPTransportStub` from the merged
   (suite + test) stub list and binds it as the TaskLocal for the test body.
3. Test body reads `HTTPTransportStub.current` and passes it explicitly to
   the client under test (constructor injection — matches how `HTTPTransport`
   is already wired into clients elsewhere in the codebase).
4. Each `send`/`stream` call the client makes pops the next stub, checks
   method + full URL, optionally asserts a curl snapshot of the request, and
   returns the stubbed response.
5. At scope exit, any unconsumed stub fails the test.

## Error handling

Every failure path uses `Issue.record` to fail the test — this is the real
signal, independent of whatever the thrown `HTTPError` triggers in the code
under test's own error handling. A test can't pass by accident just because
the client under test happens to swallow the thrown error.

## Example usage

```swift
@Test(.http(stubs: [
  .post("https://example.com/auth/v1/otp", status: 200, matches: {
    """
    curl 'https://example.com/auth/v1/otp' \
    	--header 'Content-Type: application/json'
    """
  }) {
    .string(#"{"message_id":"123"}"#)
  }
]))
func signInWithOTP() async throws {
  let client = MyClient(transport: HTTPTransportStub.current)
  try await client.signInWithOTP(email: "a@b.com")
}
```

## Testing plan

- Unit-test `HTTPTransportStub`'s match/consume/leftover logic directly,
  without going through the trait.
- A thin trait-wiring test verifying `.http(stubs:)` actually binds the
  TaskLocal and that mismatch/leftover/out-of-scope paths record issues (via
  `withKnownIssue`).
- No integration with `Replay`, `Mocker`, or the app-level `TestHelpers`
  target.
