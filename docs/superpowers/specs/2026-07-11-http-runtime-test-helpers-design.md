# HTTPRuntimeTestHelpers design

## Goal

First-party Swift Testing support for stubbing `HTTPTransport`-issued requests: a
custom trait (`.http(stubs:)`) that lets a test declare canned responses and
works under parallel test execution, plus a standalone `assertHTTPRequests`
helper to assert the shape of the outgoing request(s) via an inline curl
snapshot. Response stubbing and request-shape assertion are separate
concerns.

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
    body: @Sendable @escaping () -> HTTPStubBody = { .empty }
  ) -> HTTPStub
  // .get, .put, .patch, .delete, .head — same shape
}
```

- `url` is compared against the full outgoing URL string, including query,
  exactly (no path-only or pattern matching).
- `HTTPStub` only ever describes the canned *response*. Asserting the shape
  of the outgoing *request* is a separate concern — see `assertHTTPRequests`
  below.

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
  private var consumedRequests: [HTTPRequest] = []
  init(stubs: [HTTPStub]) { pending = stubs }

  func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?) async throws(HTTPError) -> HTTPResponse {
    consumedRequests.append(request)
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
    return HTTPResponse(head: HTTPResponseHead(status: stub.status, headers: stub.headers), body: stub.bodyData)
  }

  func stream(_ request: HTTPRequest) async throws(HTTPError) -> HTTPResponseStream {
    // same pop/compare/record logic as send, yields .stream(AsyncStream<Data>) chunks
  }

  func assertAllConsumed() {
    for stub in pending {
      Issue.record("Stub for \(stub.method) \(stub.url) was never consumed")
    }
  }

  /// Count of requests recorded so far — `assertHTTPRequests` snapshots this
  /// before running its operation, then diffs against it after.
  var requestCount: Int { consumedRequests.count }

  /// Requests recorded from `index` onward.
  func requests(since index: Int) -> [HTTPRequest] { Array(consumedRequests[index...]) }

  /// Stubs not yet consumed — read by `HTTPStubTrait` to merge a suite-level
  /// queue with a nested test-level one.
  fileprivate var remainingStubs: [HTTPStub] { pending }
}
```

`current` is always non-optional. Outside a `.http` scope, accessing it
records an issue immediately (via `Issue.record`) and hands back an
empty-queue instance — any subsequent request against it fails through the
normal "no stubs remaining" path rather than crashing.

### `curlCommand(for:)` and `assertHTTPRequests`

A single formatting function renders an `HTTPRequest` as a curl command
(method, URL, sorted headers, escaped body) — mirroring the conventions of
the existing `Sources/TestHelpers/URLRequestSnapshot.swift` `._curl` strategy
for consistency across the codebase's curl-snapshot output, but implemented
independently against `HTTPRequest` so `HTTPRuntimeTestHelpers` has no
dependency on `TestHelpers`.

```swift
func curlCommand(for request: HTTPRequest) -> String { ... }

func assertHTTPRequests<R>(
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

`assertHTTPRequests` requires an ambient `HTTPTransportStub.current` (i.e.
must run inside a `.http(stubs:)` scope) — it reads back whatever requests
that transport recorded while consuming stubs during `operation()`, so
there's one source of truth for "what requests happened," not two competing
mechanisms. Multiple requests in one `operation()` render as multiple curl
commands joined by a blank line, in call order.

`matches:` defaults to `nil`, same as `assertInlineSnapshot` itself, so a
first pass can omit it and let the library auto-write the recorded literal
into the call site on the first (intentionally failing) run —
`syntaxDescriptor: .init(trailingClosureOffset: 1)` is required for that
rewrite to target the right trailing closure, since `matches:` is the
*second* trailing closure here (`operation` is the first, unlabeled one).

### `HTTPStubTrait`

Usable at both `@Test` and `@Suite` level. Suite-level stubs are prepended;
a `@Test`-level trait on top appends its own stubs to whatever the suite
already queued, preserving order. Defined in the same file as
`HTTPTransportStub` so it can reach its `fileprivate remainingStubs`.

```swift
public struct HTTPStubTrait: TestTrait, SuiteTrait, TestScoping {
  let stubs: [HTTPStub]

  public func provideScope(
    for test: Test, testCase: Test.Case?, performing function: () async throws -> Void
  ) async throws {
    let outerStubs = await HTTPTransportStub._current?.remainingStubs ?? []
    let transport = HTTPTransportStub(stubs: outerStubs + stubs)
    try await HTTPTransportStub.$_current.withValue(transport) {
      try await function()
      await transport.assertAllConsumed()
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
4. Each `send`/`stream` call the client makes is recorded, pops the next
   stub, checks method + full URL, and returns the stubbed response.
5. Optionally, the test wraps a call in `assertHTTPRequests { ... } matches:
   { ... }` to assert the curl rendering of whatever requests fired during
   that call.
6. At scope exit, any unconsumed stub fails the test.

## Error handling

Every failure path uses `Issue.record` to fail the test — this is the real
signal, independent of whatever the thrown `HTTPError` triggers in the code
under test's own error handling. A test can't pass by accident just because
the client under test happens to swallow the thrown error.

## Example usage

```swift
@Test(.http(stubs: [
  .post("https://example.com/auth/v1/otp", status: 200) {
    .string(#"{"message_id":"123"}"#)
  }
]))
func signInWithOTP() async throws {
  let client = MyClient(transport: HTTPTransportStub.current)
  try await assertHTTPRequests {
    try await client.signInWithOTP(email: "a@b.com")
  } matches: {
    """
    curl 'https://example.com/auth/v1/otp' \
    	--header 'Content-Type: application/json'
    """
  }
}
```

## Testing plan

- Unit-test `HTTPTransportStub`'s match/consume/leftover logic directly,
  without going through the trait.
- Unit-test `curlCommand(for:)` directly against representative `HTTPRequest`
  values (headers, query, body variants).
- A thin trait-wiring test verifying `.http(stubs:)` actually binds the
  TaskLocal and that mismatch/leftover/out-of-scope paths record issues (via
  `withKnownIssue`).
- A test verifying `assertHTTPRequests` correctly slices only the requests
  made during its own `operation()` closure — not ones made before it, and
  not ones made by a second `assertHTTPRequests` call later in the same test.
- No integration with `Replay`, `Mocker`, or the app-level `TestHelpers`
  target.
