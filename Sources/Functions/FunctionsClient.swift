public import Foundation
public import HTTPTypes
public import Helpers
import IssueReporting
public import Logging

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

let version = Helpers.version

/// A client for invoking Supabase Edge Functions.
///
/// Obtain one from `SupabaseClient.functions`, or build one standalone with
/// ``init(configuration:)``.
///
/// ```swift
/// // JSON in, typed JSON out
/// let order: Order = try await supabase.functions.invoke("get-order", body: .json(["id": 42]))
///
/// // Fire and forget
/// try await supabase.functions.invoke("send-email", body: .json(email))
///
/// // GET with a query, raw response
/// let response = try await supabase.functions.invoke(
///   "report",
///   options: .init(method: .get, query: [.init(name: "month", value: "2026-09")])
/// )
/// print(response.status, response.region ?? "unknown region")
/// ```
///
/// ## Topics
///
/// ### Creating a Client
/// - ``Configuration``
/// - ``init(configuration:)``
/// - ``configuration``
///
/// ### Invoking Functions
/// - ``invoke(_:body:options:)``
/// - ``invoke(_:body:options:as:decoder:)``
///
/// ### Streaming Responses
/// - ``stream(_:body:options:)``
///
/// ### Timeouts
/// - ``requestIdleTimeout``
public struct FunctionsClient: Sendable {
  /// The settings a ``FunctionsClient`` is created with.
  public struct Configuration: Sendable {
    /// The Functions base URL, for example `https://<ref>.supabase.co/functions/v1`.
    public var url: URL

    /// Headers sent with every request.
    ///
    /// Must not carry `Authorization`: a static bearer would win over every token. Pass the
    /// token through ``accessToken`` instead.
    public var headers: HTTPFields

    /// The region to invoke functions in. `nil` lets the platform choose.
    public var region: FunctionRegion?

    /// The transport and middleware chain every request goes through.
    public var http: HTTPClientConfiguration

    /// A logger for request and response diagnostics.
    public var logger: Logging.Logger

    /// The decoder ``FunctionsClient/invoke(_:body:options:as:decoder:)`` and
    /// ``FunctionResponse/decode(as:decoder:)`` use when no per-call `decoder:` is given.
    ///
    /// Defaults to the SDK decoder, which reads ISO 8601 dates (the format a TypeScript
    /// function's `JSON.stringify` writes) into `Date`.
    public var decoder: JSONDecoder

    /// Resolved for every request and sent as `Authorization: Bearer <token>` unless the request
    /// already carries `Authorization`. `nil` (the default) sends no bearer token.
    public var accessToken: (@Sendable () async throws -> String?)?

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - url: The Functions base URL.
    ///   - headers: Headers sent with every request. Must not carry `Authorization`.
    ///   - region: The region to invoke functions in. `nil` lets the platform choose.
    ///   - http: The transport and middleware chain every request goes through.
    ///   - logger: A logger for request and response diagnostics.
    ///   - decoder: The decoder used when a call does not pass its own.
    ///   - accessToken: Resolved for every request and sent as a bearer token when the request
    ///     does not already carry `Authorization`.
    public init(
      url: URL,
      headers: HTTPFields = [:],
      region: FunctionRegion? = nil,
      http: HTTPClientConfiguration = .init(),
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.functions"),
      decoder: JSONDecoder = .supabase(),
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.url = url
      self.headers = headers
      self.region = region
      self.http = http
      self.logger = logger
      self.decoder = decoder
      self.accessToken = accessToken
    }
  }

  /// The maximum time an Edge Function may be idle before the gateway returns a 504 (150 seconds).
  ///
  /// This is the idle timeout for every invocation unless ``Configuration/http``'s `timeout` or
  /// ``FunctionInvokeOptions/timeout`` sets another.
  public static let requestIdleTimeout: Duration = .seconds(150)

  /// The configuration this client was created with.
  public let configuration: Configuration

  private let http: HTTPClient

  /// Creates a Functions client.
  ///
  /// Traps if `configuration.url` has no host. The URL is fixed at construction, so a bad one
  /// is a programmer error, and trapping reports it where it was introduced instead of as an
  /// opaque transport failure on the first call.
  public init(configuration: Configuration) {
    guard configuration.url.host(percentEncoded: false) != nil else {
      preconditionFailure(
        "FunctionsClient configured with a URL that has no host: \(configuration.url)")
    }
    if configuration.headers[.authorization] != nil {
      reportIssue(
        "`FunctionsClient.Configuration.headers` carries `Authorization`. A static bearer wins "
          + "over every token; pass it through `Configuration.accessToken` instead.")
    }
    self.configuration = configuration

    var logger = configuration.logger
    logger[metadataKey: "system"] = "functions"
    // After the caller's middlewares, so none of them sees the token; before the logger, so
    // the logged request is the one on the wire.
    let accessToken = configuration.accessToken.map { AccessTokenMiddleware(getAccessToken: $0) }
    http = HTTPClient(
      configuration: configuration.http,
      appending: (accessToken.map { [$0] } ?? []) + [LoggerInterceptor(logger: logger)],
      defaultTimeout: Self.requestIdleTimeout
    )
  }

  /// Invokes a function and returns the buffered response.
  ///
  /// ```swift
  /// let response = try await functions.invoke("render", options: .init(method: .get))
  /// let pdf = response.body
  /// ```
  ///
  /// - Parameters:
  ///   - name: The function's slug. May contain a sub-path, like `"api/users/1"`.
  ///   - body: What to send. `nil` sends no body.
  ///   - options: Method, headers, query, region and timeout for this call.
  /// - Returns: The status, headers and body the function answered with.
  /// - Throws: ``FunctionsError`` for a relay failure, a non-2xx status or a transport failure;
  ///   `CancellationError` if the task is cancelled; whatever a custom transport, middleware or
  ///   ``Configuration/accessToken`` closure throws.
  @discardableResult
  public func invoke(
    _ name: String,
    body: FunctionBody? = nil,
    options: FunctionInvokeOptions = .init()
  ) async throws -> FunctionResponse {
    let (head, responseBody) = try await FunctionsAPI.exchange(
      name: name, body: body, options: options, configuration: configuration, http: http)
    var data = Data()
    do {
      if let responseBody { data = try await Data(collecting: responseBody, upTo: .max) }
    } catch {
      throw FunctionsAPI.mapTransportError(error)
    }
    return FunctionResponse(
      status: head.status, headers: head.headerFields, body: data, decoder: configuration.decoder)
  }

  /// Invokes a function and JSON-decodes the response body.
  ///
  /// ```swift
  /// let order: Order = try await functions.invoke("get-order")
  /// let order = try await functions.invoke("get-order", as: Order.self)
  /// ```
  ///
  /// Decoding runs in the caller's isolation, so a `Decodable` declared in a main-actor
  /// module works.
  ///
  /// - Parameters:
  ///   - name: The function's slug.
  ///   - body: What to send. `nil` sends no body.
  ///   - options: Method, headers, query, region and timeout for this call.
  ///   - type: The type to decode. Inferred from the call site when omitted.
  ///   - decoder: Overrides ``Configuration/decoder`` for this call.
  /// - Returns: The decoded body.
  /// - Throws: ``FunctionsError`` with kind ``FunctionsError/Kind-swift.struct/decoding`` when a
  ///   2xx body does not decode as `T`, or the same errors as ``invoke(_:body:options:)``.
  public func invoke<T: Decodable>(
    _ name: String,
    body: FunctionBody? = nil,
    options: FunctionInvokeOptions = .init(),
    as type: T.Type = T.self,
    decoder: JSONDecoder? = nil
  ) async throws -> T {
    try await invoke(name, body: body, options: options).decode(as: type, decoder: decoder)
  }

  /// Invokes a function and returns as soon as the response head arrives. The body streams.
  ///
  /// Use it for `text/event-stream` and large responses. Iterate
  /// ``FunctionStreamResponse/body`` once; cancelling the iterating task closes the connection.
  /// Chunk boundaries follow the network, not the payload: a server-sent event or a JSON line
  /// may arrive split across chunks, so frame them with a parser of your own.
  ///
  /// ```swift
  /// let response = try await functions.stream("chat", body: .json(prompt))
  /// for try await chunk in response.body {
  ///   parser.feed(chunk)
  /// }
  /// ```
  ///
  /// > Note: On Linux the body is delivered whole when the server closes the connection
  /// > (`URLSessionTransport` buffers it there).
  ///
  /// - Parameters:
  ///   - name: The function's slug. May contain a sub-path, like `"api/users/1"`.
  ///   - body: What to send. `nil` sends no body.
  ///   - options: Method, headers, query, region and timeout for this call.
  /// - Returns: The status and headers, and the body still to be read.
  /// - Throws: ``FunctionsError`` for a relay failure, a non-2xx status or a transport failure
  ///   before the head arrives; `CancellationError` if the task is cancelled; whatever a custom
  ///   transport, middleware or ``Configuration/accessToken`` closure throws.
  public func stream(
    _ name: String,
    body: FunctionBody? = nil,
    options: FunctionInvokeOptions = .init()
  ) async throws -> FunctionStreamResponse {
    let (head, responseBody) = try await FunctionsAPI.exchange(
      name: name, body: body, options: options, configuration: configuration, http: http)
    return FunctionStreamResponse(
      status: head.status,
      headers: head.headerFields,
      body: responseBody?.mapError { FunctionsAPI.mapTransportError($0) } ?? HTTPBody(Data())
    )
  }
}
