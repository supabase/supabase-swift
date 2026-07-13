# Functions → HTTPRuntime Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `Sources/Functions`'s internal HTTP plumbing from `Helpers.HTTPClient`/`Helpers.HTTPRequest`/`Helpers.HTTPResponse` to the new `HTTPRuntime` target, with zero changes to `FunctionsClient`'s public API.

**Architecture:** A private `FetchHandlerTransport` adapts the stored `fetch:` closure to `HTTPRuntime.HTTPTransport` for the buffered `invoke*` path. The streaming path (`_invokeWithStreamedResponse`) swaps its custom `URLSession` + delegate for `HTTPRuntime.URLSessionTransport.stream(_:)` directly. Headers move from `HTTPTypes.HTTPFields` to plain `[String: String]` throughout.

**Tech Stack:** Swift 6.1, `HTTPRuntime` (already merged in this branch), existing `Helpers`/`ConcurrencyExtras` dependencies.

## Global Constraints

- Zero changes to `FunctionsClient`'s public API: `FetchHandler` typealias, both public initializers, `invoke`/`invoke(decode:)`/`invoke(decoder:)`, `_invokeWithStreamedResponse`, `setAuth`, every `FunctionsError` case — all stay exactly as today.
- No promotion of `HTTPRuntime` from `package` to `public` access.
- No changes to `Sources/Helpers` — `HTTPClientType`/`HTTPClient`/`LoggerInterceptor`/`Helpers.HTTPRequest`/`Helpers.HTTPResponse` stay exactly as they are (Auth, PostgREST, Realtime, Storage still depend on them).
- No test-framework migration — `Tests/FunctionsTests` stays on XCTest + Mocker.
- Request/response logging (`logger:` parameter) is dropped for now — the parameter stays in the public API but becomes inert. Not a bug, a deliberate deferred scope cut (see spec).
- The streaming path's 150s `requestIdleTimeout` is dropped for now — it falls back to `sessionConfiguration`'s default timeout (~60s). Deliberate deferred scope cut (see spec).
- `HTTPError.transport(underlying)` must never leak to callers — `FunctionsClient` catches it at both call sites and re-throws/finishes with `underlying` directly. This is verified by an existing test (`testInvoke_shouldThrow_URLError_badServerResponse`), not just a design intention.
- `invoke(_:options:decode:)`'s `decode` closure keeps its exact `(Data, HTTPURLResponse) throws -> Response` signature — synthesize the `HTTPURLResponse` from `HTTPResponseHead` + the request URL.
- Spec: `docs/superpowers/specs/2026-07-11-functions-httpruntime-migration-design.md` — read it for full rationale; this plan implements it exactly.

---

## File Structure

- `Package.swift` — `Functions` target: drop `HTTPTypes` product dependency, add `HTTPRuntime` target dependency.
- `Sources/Functions/Types.swift` — `FunctionInvokeOptions.headers` becomes `[String: String]`; `httpMethod(_:)` returns `HTTPRuntime.HTTPMethod?`.
- `Sources/Functions/FunctionsClient.swift` — `MutableState.headers` becomes `[String: String]`; adds private `FetchHandlerTransport`; `buildRequest` returns `HTTPRuntime.HTTPRequest`; `rawInvoke` and `_invokeWithStreamedResponse` rewritten; `StreamResponseDelegate` deleted.
- `Tests/FunctionsTests/FunctionInvokeOptionsTests.swift` — `import HTTPTypes` → `import HTTPRuntime`; `.contentType` subscript → `"Content-Type"` string key; `testMethod()`'s expected type → `HTTPMethod`.
- `Tests/FunctionsTests/FunctionsClientTests.swift` — remove the dead `import HTTPTypes` line.

No new files. `Tests/FunctionsTests/RequestTests.swift` and `Tests/FunctionsTests/FunctionsErrorTests.swift` need no changes — they don't reference `HTTPTypes`/`HTTPFields`.

---

### Task 1: Migrate headers + buffered `invoke` path to HTTPRuntime

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/Functions/Types.swift`
- Modify: `Sources/Functions/FunctionsClient.swift` (headers, initializers, `buildRequest`, `FetchHandlerTransport`, `rawInvoke`, `invoke(decode:)`; leaves `_invokeWithStreamedResponse`/`StreamResponseDelegate` using a one-line stopgap, fully migrated in Task 2)
- Modify: `Tests/FunctionsTests/FunctionInvokeOptionsTests.swift`
- Modify: `Tests/FunctionsTests/FunctionsClientTests.swift`

**Interfaces:**
- Consumes: `HTTPRuntime.HTTPMethod` (`.get`/`.post`/`.put`/`.patch`/`.delete`/`.head`), `HTTPRequest(method:url:headers:body:)`, `HTTPBody.data(Data)`, `HTTPTransport` protocol (`send(_:uploadProgress:) async throws(HTTPError) -> HTTPResponse`, plus its 1-arg `send(_:)` convenience), `HTTPResponse(head:body:)`, `HTTPResponseHead(status:headers:)` with `.header(_:)` (case-insensitive lookup), `HTTPError.transport(any Error)`.
- Produces: `FunctionInvokeOptions.headers: [String: String]`, `FunctionInvokeOptions.httpMethod(_:) -> HTTPMethod?`, `FunctionsClient.buildRequest(functionName:options:) -> HTTPRequest` (used again, unmodified signature, by Task 2's streaming rewrite), `FetchHandlerTransport` (private struct with `static func makeURLRequest(_:) -> URLRequest`, also reused by Task 2's stopgap-turned-removed code).

- [ ] **Step 1: Update `Package.swift`**

Find the `Functions` target:

```swift
    .target(
      name: "Functions",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        "Helpers",
      ]
    ),
```

Replace it with:

```swift
    .target(
      name: "Functions",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        "Helpers",
        "HTTPRuntime",
      ]
    ),
```

- [ ] **Step 2: Rewrite `Sources/Functions/Types.swift`**

Replace the file's entire contents with:

```swift
public import Foundation
import HTTPRuntime
import Helpers

/// An error type representing various errors that can occur while invoking functions.
public enum FunctionsError: Error, LocalizedError {
  /// Error indicating a relay error while invoking the Edge Function.
  case relayError
  /// Error indicating a non-2xx status code returned by the Edge Function.
  case httpError(code: Int, data: Data)

  /// A localized description of the error.
  public var errorDescription: String? {
    switch self {
    case .relayError:
      "Relay Error invoking the Edge Function"
    case .httpError(let code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    }
  }
}

/// Options for invoking a function.
public struct FunctionInvokeOptions: Sendable {
  /// Method to use in the function invocation.
  let method: Method?
  /// Headers to be included in the function invocation.
  let headers: [String: String]
  /// Body data to be sent with the function invocation.
  let body: Data?
  /// The Region to invoke the function in.
  let region: String?
  /// The query to be included in the function invocation.
  let query: [URLQueryItem]

  /// Creates options for a function invocation with an encodable body.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - query: Query items appended to the function URL.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region string to invoke the function in.
  ///   - body: The body to encode and send. Strings are sent as `text/plain`, `Data` as
  ///     `application/octet-stream`, and all other `Encodable` values as JSON.
  ///   - encoder: The JSON encoder used when `body` is encoded as JSON.
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil,
    body: some Encodable,
    encoder: JSONEncoder = JSONEncoder()
  ) {
    var defaultHeaders: [String: String] = [:]

    switch body {
    case let string as String:
      defaultHeaders["Content-Type"] = "text/plain"
      self.body = string.data(using: .utf8)
    case let data as Data:
      defaultHeaders["Content-Type"] = "application/octet-stream"
      self.body = data
    default:
      defaultHeaders["Content-Type"] = "application/json"
      self.body = try? encoder.encode(body)
    }

    self.method = method
    self.headers = defaultHeaders.merging(headers) { $1 }
    self.region = region
    self.query = query
  }

  /// Creates options for a function invocation with no body.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - query: Query items appended to the function URL.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region string to invoke the function in.
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil
  ) {
    self.method = method
    self.headers = headers
    self.region = region
    self.query = query
    body = nil
  }

  /// The HTTP method to use when invoking a function.
  public enum Method: String, Sendable {
    /// Performs an HTTP GET request.
    case get = "GET"
    /// Performs an HTTP POST request.
    case post = "POST"
    /// Performs an HTTP PUT request.
    case put = "PUT"
    /// Performs an HTTP PATCH request.
    case patch = "PATCH"
    /// Performs an HTTP DELETE request.
    case delete = "DELETE"
  }

  static func httpMethod(_ method: Method?) -> HTTPMethod? {
    switch method {
    case .get:
      .get
    case .post:
      .post
    case .put:
      .put
    case .patch:
      .patch
    case .delete:
      .delete
    case nil:
      nil
    }
  }
}

/// A Supabase Edge Function deployment region.
public enum FunctionRegion: String, Sendable {
  /// Asia Pacific (Tokyo).
  case apNortheast1 = "ap-northeast-1"
  /// Asia Pacific (Seoul).
  case apNortheast2 = "ap-northeast-2"
  /// Asia Pacific (Mumbai).
  case apSouth1 = "ap-south-1"
  /// Asia Pacific (Singapore).
  case apSoutheast1 = "ap-southeast-1"
  /// Asia Pacific (Sydney).
  case apSoutheast2 = "ap-southeast-2"
  /// Canada (Central).
  case caCentral1 = "ca-central-1"
  /// Europe (Frankfurt).
  case euCentral1 = "eu-central-1"
  /// Europe (Ireland).
  case euWest1 = "eu-west-1"
  /// Europe (London).
  case euWest2 = "eu-west-2"
  /// Europe (Paris).
  case euWest3 = "eu-west-3"
  /// South America (São Paulo).
  case saEast1 = "sa-east-1"
  /// US East (N. Virginia).
  case usEast1 = "us-east-1"
  /// US West (N. California).
  case usWest1 = "us-west-1"
  /// US West (Oregon).
  case usWest2 = "us-west-2"
}

extension FunctionInvokeOptions {
  /// Creates options for a function invocation with an encodable body and a typed region.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region to invoke the function in.
  ///   - body: The body to encode and send.
  ///   - encoder: The JSON encoder used when `body` is encoded as JSON.
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    body: some Encodable,
    encoder: JSONEncoder = JSONEncoder()
  ) {
    self.init(
      method: method,
      headers: headers,
      region: region?.rawValue,
      body: body,
      encoder: encoder
    )
  }

  /// Creates options for a function invocation with no body and a typed region.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region to invoke the function in.
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil
  ) {
    self.init(method: method, headers: headers, region: region?.rawValue)
  }
}
```

Only two things changed from the original: `headers: HTTPFields` → `headers: [String: String]` (and its two call sites, `defaultHeaders["Content-Type"] = ...` / `defaultHeaders.merging(headers) { $1 }`), and `httpMethod(_:) -> HTTPTypes.HTTPRequest.Method?` → `httpMethod(_:) -> HTTPMethod?`. Everything else — doc comments, `FunctionRegion`, the typed-region convenience inits — is copied verbatim.

- [ ] **Step 3: Rewrite the header-handling and initializer portion of `Sources/Functions/FunctionsClient.swift`**

Replace lines 1–150 (from the top of the file through the end of the `init(url:headers:region:decoder:http:sessionConfiguration:)` initializer) with:

```swift
import ConcurrencyExtras
public import Foundation
import HTTPRuntime
public import Helpers

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

let version = Helpers.version

/// A client for invoking Supabase Edge Functions.
///
/// Obtain an instance from ``SupabaseClient/functions`` rather than creating one directly.
///
/// ```swift
/// // Invoke and decode a response
/// let order: Order = try await supabase.functions.invoke("get-order")
///
/// // Invoke with a body and no return value
/// try await supabase.functions.invoke(
///   "send-email",
///   options: FunctionInvokeOptions(body: ["to": "user@example.com"])
/// )
/// ```
///
/// ## Topics
///
/// ### Creating a Client
/// - ``init(url:headers:region:logger:fetch:decoder:)``
/// - ``FetchHandler``
///
/// ### Invoking Functions
/// - ``invoke(_:options:decode:)``
/// - ``invoke(_:options:decoder:)``
/// - ``invoke(_:options:)``
/// - ``_invokeWithStreamedResponse(_:options:)``
///
/// ### Configuration
/// - ``decoder``
/// - ``requestIdleTimeout``
/// - ``setAuth(token:)``
public final class FunctionsClient: Sendable {
  /// A handler that performs the underlying HTTP request for a function invocation.
  public typealias FetchHandler =
    @Sendable (_ request: URLRequest) async throws -> (
      Data, URLResponse
    )

  /// The maximum time an Edge Function may run before the gateway returns a 504 error (150 seconds).
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  /// The JSON decoder used to decode function response bodies.
  public let decoder: JSONDecoder

  struct MutableState {
    /// Headers to be included in the requests.
    var headers: [String: String] = [:]
  }

  private let fetch: FetchHandler
  private let mutableState = LockIsolated(MutableState())
  private let sessionConfiguration: URLSessionConfiguration

  var headers: [String: String] {
    mutableState.headers
  }

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region string to invoke functions in.
  ///   - logger: A logger for request and response diagnostics.
  ///   - fetch: A custom fetch handler. Defaults to `URLSession.shared`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  @_disfavoredOverload
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region,
      fetch: fetch,
      decoder: decoder,
      sessionConfiguration: .default
    )
  }

  convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    decoder: JSONDecoder = JSONDecoder(),
    sessionConfiguration: URLSessionConfiguration
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region,
      decoder: decoder,
      fetch: fetch,
      sessionConfiguration: sessionConfiguration
    )
  }

  init(
    url: URL,
    headers: [String: String],
    region: String?,
    decoder: JSONDecoder = JSONDecoder(),
    fetch: @escaping FetchHandler,
    sessionConfiguration: URLSessionConfiguration = .default
  ) {
    self.url = url
    self.region = region
    self.decoder = decoder
    self.fetch = fetch
    self.sessionConfiguration = sessionConfiguration

    mutableState.withValue {
      $0.headers = headers
      if $0.headers["X-Client-Info"] == nil {
        $0.headers["X-Client-Info"] = "functions-swift/\(version)"
      }
    }
  }
```

Note: the `logger:` parameter is dropped from the internal `convenience init(...sessionConfiguration:)` and the innermost `init(...)` — only the two *public*-facing initializers still accept it (per the "logging dropped for now" constraint), and they simply don't forward it anywhere anymore.

- [ ] **Step 4: Update `setAuth` and the typed-region public initializer**

Find:

```swift
  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region to invoke functions in.
  ///   - logger: A logger for request and response diagnostics.
  ///   - fetch: A custom fetch handler. Defaults to `URLSession.shared`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region?.rawValue,
      logger: logger,
      fetch: fetch,
      decoder: decoder
    )
  }

  /// Sets or clears the JWT used in the Authorization header for subsequent requests.
  /// - Parameter token: The JWT to send, or `nil` to remove the Authorization header.
  public func setAuth(token: String?) {
    mutableState.withValue {
      if let token {
        $0.headers[.authorization] = "Bearer \(token)"
      } else {
        $0.headers[.authorization] = nil
      }
    }
  }
```

Replace it with:

```swift
  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region to invoke functions in.
  ///   - logger: A logger for request and response diagnostics.
  ///   - fetch: A custom fetch handler. Defaults to `URLSession.shared`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region?.rawValue,
      fetch: fetch,
      decoder: decoder
    )
  }

  /// Sets or clears the JWT used in the Authorization header for subsequent requests.
  /// - Parameter token: The JWT to send, or `nil` to remove the Authorization header.
  public func setAuth(token: String?) {
    mutableState.withValue {
      if let token {
        $0.headers["Authorization"] = "Bearer \(token)"
      } else {
        $0.headers["Authorization"] = nil
      }
    }
  }
```

- [ ] **Step 5: Rewrite `rawInvoke`, `buildRequest`, and add `FetchHandlerTransport`**

Find:

```swift
  private func rawInvoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> Helpers.HTTPResponse {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    let response = try await http.send(request)

    guard 200..<300 ~= response.statusCode else {
      throw FunctionsError.httpError(code: response.statusCode, data: response.data)
    }

    let isRelayError = response.headers[.xRelayError] == "true"
    if isRelayError {
      throw FunctionsError.relayError
    }

    return response
  }
```

Replace it with:

```swift
  private func rawInvoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> (data: Data, response: HTTPURLResponse) {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    let transport = FetchHandlerTransport(fetch: fetch)

    let response: HTTPResponse
    do {
      response = try await transport.send(request)
    } catch HTTPError.transport(let underlying) {
      throw underlying
    }

    guard
      let httpResponse = HTTPURLResponse(
        url: request.url, statusCode: response.head.status, httpVersion: nil,
        headerFields: response.head.headers)
    else {
      throw URLError(.badServerResponse)
    }

    guard 200..<300 ~= response.head.status else {
      throw FunctionsError.httpError(code: response.head.status, data: response.body)
    }

    if response.head.header("x-relay-error") == "true" {
      throw FunctionsError.relayError
    }

    return (response.body, httpResponse)
  }
```

Find:

```swift
  private func buildRequest(functionName: String, options: FunctionInvokeOptions)
    -> Helpers.HTTPRequest
  {
    var query = options.query
    var request = HTTPRequest(
      url: url.appendingPathComponent(functionName),
      method: FunctionInvokeOptions.httpMethod(options.method) ?? .post,
      query: query,
      headers: mutableState.headers.merging(with: options.headers),
      body: options.body,
      timeoutInterval: FunctionsClient.requestIdleTimeout
    )

    if let region = options.region ?? region {
      request.headers[.xRegion] = region
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region))
      request.query = query
    }

    return request
  }
}
```

Replace it with:

```swift
  private func buildRequest(functionName: String, options: FunctionInvokeOptions) -> HTTPRequest {
    var query = options.query
    var requestHeaders = mutableState.headers.merging(options.headers) { $1 }

    if let region = options.region ?? region {
      requestHeaders["x-region"] = region
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region))
    }

    let requestURL = url.appendingPathComponent(functionName).appendingQueryItems(query)

    return HTTPRequest(
      method: FunctionInvokeOptions.httpMethod(options.method) ?? .post,
      url: requestURL,
      headers: requestHeaders,
      body: options.body.map { HTTPBody.data($0) }
    )
  }

  /// Adapts the stored `fetch:` closure to `HTTPTransport` for the buffered `invoke*` path.
  /// Only `send(_:uploadProgress:)` is used — streaming always goes through
  /// `URLSessionTransport` directly (see `_invokeWithStreamedResponse`), never through the
  /// public `fetch:` closure, so `stream(_:)` here is unreachable.
  private struct FetchHandlerTransport: HTTPTransport {
    let fetch: FunctionsClient.FetchHandler

    func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?) async throws(HTTPError)
      -> HTTPResponse
    {
      let urlRequest = Self.makeURLRequest(request)
      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await fetch(urlRequest)
      } catch {
        throw HTTPError.transport(error)
      }
      guard let http = response as? HTTPURLResponse else {
        throw HTTPError.transport(URLError(.badServerResponse))
      }
      var headers: [String: String] = [:]
      for (key, value) in http.allHeaderFields {
        if let key = key as? String, let value = value as? String {
          headers[key] = value
        }
      }
      return HTTPResponse(head: HTTPResponseHead(status: http.statusCode, headers: headers), body: data)
    }

    func stream(_ request: HTTPRequest) async throws(HTTPError) -> HTTPResponseStream {
      fatalError("FetchHandlerTransport does not support streaming; use URLSessionTransport instead")
    }

    static func makeURLRequest(_ request: HTTPRequest) -> URLRequest {
      var urlRequest = URLRequest(url: request.url, timeoutInterval: FunctionsClient.requestIdleTimeout)
      urlRequest.httpMethod = request.method.rawValue
      for (name, value) in request.headers {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }
      if case .data(let payload) = request.body {
        urlRequest.httpBody = payload
      }
      return urlRequest
    }
  }
}
```

Note the closing `}` at the end — `buildRequest` and `FetchHandlerTransport` are the last members before the class closes; `_invokeWithStreamedResponse` and `StreamResponseDelegate` (further up in the file, untouched by this step) stay exactly where they are between `setAuth`/`invoke*` and this point.

- [ ] **Step 6: Update `invoke(_:options:decode:)`'s call site**

Find:

```swift
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws -> Response {
    let response = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )
    return try decode(response.data, response.underlyingResponse)
  }
```

Replace it with:

```swift
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws -> Response {
    let (data, response) = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )
    return try decode(data, response)
  }
```

- [ ] **Step 7: Apply the one-line stopgap so `_invokeWithStreamedResponse` still compiles (it's fully migrated in Task 2)**

Find, inside `_invokeWithStreamedResponse` (this method itself is untouched otherwise in this task):

```swift
    let urlRequest = buildRequest(functionName: functionName, options: invokeOptions).urlRequest
```

Replace it with:

```swift
    let urlRequest = FetchHandlerTransport.makeURLRequest(
      buildRequest(functionName: functionName, options: invokeOptions))
```

`HTTPRuntime.HTTPRequest` (which `buildRequest` now returns) has no `.urlRequest` convenience property the way `Helpers.HTTPRequest` did — `FetchHandlerTransport.makeURLRequest` is the equivalent conversion, already written in Step 5. Everything else in `_invokeWithStreamedResponse` and all of `StreamResponseDelegate` stay exactly as they are until Task 2.

- [ ] **Step 8: Fix `Tests/FunctionsTests/FunctionInvokeOptionsTests.swift`**

Replace the file's entire contents with:

```swift
import HTTPRuntime
import XCTest

@testable import Functions

final class FunctionInvokeOptionsTests: XCTestCase {
  func test_initWithStringBody() {
    let options = FunctionInvokeOptions(body: "string value")
    XCTAssertEqual(options.headers["Content-Type"], "text/plain")
    XCTAssertNotNil(options.body)
  }

  func test_initWithDataBody() {
    let options = FunctionInvokeOptions(body: "binary value".data(using: .utf8)!)
    XCTAssertEqual(options.headers["Content-Type"], "application/octet-stream")
    XCTAssertNotNil(options.body)
  }

  func test_initWithEncodableBody() {
    struct Body: Encodable {
      let value: String
    }
    let options = FunctionInvokeOptions(body: Body(value: "value"))
    XCTAssertEqual(options.headers["Content-Type"], "application/json")
    XCTAssertNotNil(options.body)
  }

  func test_initWithEncodableBodyAndCustomEncoder() {
    struct Body: Encodable {
      let userName: String
    }

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    let options = FunctionInvokeOptions(body: Body(userName: "test"), encoder: encoder)
    XCTAssertEqual(options.headers["Content-Type"], "application/json")

    let json = try! JSONSerialization.jsonObject(with: options.body!) as! [String: Any]
    XCTAssertNotNil(json["user_name"])
    XCTAssertNil(json["userName"])
  }

  func test_initWithCustomContentType() {
    let boundary = "Boundary-\(UUID().uuidString)"
    let contentType = "multipart/form-data; boundary=\(boundary)"
    let options = FunctionInvokeOptions(
      headers: ["Content-Type": contentType],
      body: "binary value".data(using: .utf8)!
    )
    XCTAssertEqual(options.headers["Content-Type"], contentType)
    XCTAssertNotNil(options.body)
  }

  func testMethod() {
    let testCases: [FunctionInvokeOptions.Method: HTTPMethod] = [
      .get: .get,
      .post: .post,
      .put: .put,
      .patch: .patch,
      .delete: .delete,
    ]

    for (method, expected) in testCases {
      XCTAssertEqual(FunctionInvokeOptions.httpMethod(method), expected)
    }
  }
}
```

`HTTPRuntime` resolves here without any `Package.swift` change to the `FunctionsTests` target — it's transitively available via `Functions`'s new dependency on it, the same mechanism that made the old `import HTTPTypes` resolve here before without an explicit product entry.

- [ ] **Step 9: Remove the dead import in `Tests/FunctionsTests/FunctionsClientTests.swift`**

Find line 2:

```swift
import HTTPTypes
```

Delete it. Nothing else in that file references `HTTPTypes` (confirmed: `Mock(... data: [.post: ...])`'s `.post` resolves to `Mocker`'s own `HTTPMethod` enum, not `HTTPTypes`).

- [ ] **Step 10: Run the full existing test suite**

This is a refactor of already-tested code, not new functionality — there's no new test to write first. The existing suite is the correctness oracle; the goal of this step is confirming it still passes unmodified against the new implementation.

Run: `swift test --filter FunctionsTests`
Expected: all tests in `FunctionsClientTests`, `RequestTests`, `FunctionInvokeOptionsTests`, `FunctionsErrorTests` pass, with no snapshot mismatches.

If a curl-snapshot test (`FunctionsClientTests.swift` or `RequestTests.swift`) fails with a text diff, do not re-record it — per the spec, that means the `HTTPRequest ↔ URLRequest` conversion introduced a real difference (header casing, query order, body encoding) that needs to be fixed in `FetchHandlerTransport.makeURLRequest` or `buildRequest`, not papered over. If `testInvoke_shouldThrow_URLError_badServerResponse` fails, check that the `catch HTTPError.transport(let underlying) { throw underlying }` unwrap in `rawInvoke` (Step 5) is in place and executes before the status-code check.

- [ ] **Step 11: Run the full package build**

Run: `swift build`
Expected: clean build, no warnings from `Functions`.

- [ ] **Step 12: Commit**

```bash
git add Package.swift Sources/Functions/Types.swift Sources/Functions/FunctionsClient.swift Tests/FunctionsTests/FunctionInvokeOptionsTests.swift Tests/FunctionsTests/FunctionsClientTests.swift
git commit -m "refactor(functions): migrate headers and buffered invoke path to HTTPRuntime"
```

---

### Task 2: Migrate the streaming path to `URLSessionTransport`, remove `StreamResponseDelegate`

**Files:**
- Modify: `Sources/Functions/FunctionsClient.swift` (`_invokeWithStreamedResponse` rewritten; `StreamResponseDelegate` class deleted)

**Interfaces:**
- Consumes: `HTTPRuntime.URLSessionTransport(configuration:)`, `.stream(_:) async throws(HTTPError) -> HTTPResponseStream`, `HTTPResponseStream.head: HTTPResponseHead` / `.body: AsyncThrowingStream<Data, any Error>`, `HTTPResponseHead.status`/`.header(_:)`, `HTTPError.transport(any Error)`. `buildRequest(functionName:options:) -> HTTPRequest` (from Task 1, unchanged signature).
- Produces: nothing new — `_invokeWithStreamedResponse`'s public signature is unchanged (`(_ functionName: String, options: FunctionInvokeOptions) -> AsyncThrowingStream<Data, any Error>`, no `async`, no `throws`).

- [ ] **Step 1: Replace `_invokeWithStreamedResponse` and delete `StreamResponseDelegate`**

Find (this is the rest of the file from Task 1's Step 7 stopgap through the end of the file):

```swift
  public func _invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> AsyncThrowingStream<Data, any Error> {
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    let delegate = StreamResponseDelegate(continuation: continuation)

    let session = URLSession(
      configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)

    let urlRequest = FetchHandlerTransport.makeURLRequest(
      buildRequest(functionName: functionName, options: invokeOptions))

    let task = session.dataTask(with: urlRequest)
    task.resume()

    continuation.onTermination = { _ in
      task.cancel()

      // Hold a strong reference to delegate until continuation terminates.
      _ = delegate
    }

    return stream
  }
```

(the code above already reflects Task 1's Step 7 stopgap edit — replace it with:)

```swift
  public func _invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> AsyncThrowingStream<Data, any Error> {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    let transport = URLSessionTransport(configuration: sessionConfiguration)

    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()

    let task = Task {
      do {
        let responseStream = try await transport.stream(request)

        guard 200..<300 ~= responseStream.head.status else {
          throw FunctionsError.httpError(code: responseStream.head.status, data: Data())
        }
        if responseStream.head.header("x-relay-error") == "true" {
          throw FunctionsError.relayError
        }

        for try await chunk in responseStream.body {
          continuation.yield(chunk)
        }
        continuation.finish()
      } catch HTTPError.transport(let underlying) {
        continuation.finish(throwing: underlying)
      } catch {
        continuation.finish(throwing: error)
      }
    }

    continuation.onTermination = { _ in task.cancel() }

    return stream
  }
```

Then find, at the bottom of the file, and delete entirely:

```swift
final class StreamResponseDelegate: NSObject, URLSessionDataDelegate, Sendable {
  let continuation: AsyncThrowingStream<Data, any Error>.Continuation

  init(continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
    self.continuation = continuation
  }

  func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
    continuation.yield(data)
  }

  func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
    continuation.finish(throwing: error)
  }

  func urlSession(
    _: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    defer {
      completionHandler(.allow)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      continuation.finish(throwing: URLError(.badServerResponse))
      return
    }

    guard 200..<300 ~= httpResponse.statusCode else {
      let error = FunctionsError.httpError(
        code: httpResponse.statusCode,
        data: Data()
      )
      continuation.finish(throwing: error)
      return
    }

    let isRelayError = httpResponse.value(forHTTPHeaderField: "x-relay-error") == "true"
    if isRelayError {
      continuation.finish(throwing: FunctionsError.relayError)
    }
  }
}
```

The file now ends with the closing `}` of `FetchHandlerTransport` (from Task 1's Step 5).

- [ ] **Step 2: Run the streaming-specific tests**

This is a refactor of already-tested code — the goal is confirming existing streaming tests still pass, not writing new ones.

Run: `swift test --filter FunctionsTests.FunctionsClientTests/testInvokeWithStreamedResponse`
Run: `swift test --filter FunctionsTests.FunctionsClientTests/testInvokeWithStreamedResponseHTTPError`
Run: `swift test --filter FunctionsTests.FunctionsClientTests/testInvokeWithStreamedResponseRelayError`
Expected: all three pass.

- [ ] **Step 3: Run the full `FunctionsTests` suite**

Run: `swift test --filter FunctionsTests`
Expected: all tests pass (no regressions in the buffered-path tests from Task 1).

- [ ] **Step 4: Run the full package build**

Run: `swift build`
Expected: clean build. Confirm `NSObject`/`URLSessionDataDelegate` are no longer referenced anywhere in `Sources/Functions/FunctionsClient.swift` (the only place that used them was the now-deleted `StreamResponseDelegate`).

- [ ] **Step 5: Format and spell-check**

Run: `./scripts/format.sh`
Expected: exits 0, no unexpected diffs beyond this task's own files.

Run: `./scripts/spell-check.sh`
Expected: exits 0. If it flags a new word, add it to `dictionary.txt` under a `# Terms from the Functions HTTPRuntime migration.` section and re-run until clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/Functions/FunctionsClient.swift
git commit -m "refactor(functions): migrate streaming path to URLSessionTransport"
```

If Step 5 touched `dictionary.txt`, include it in this commit too.
