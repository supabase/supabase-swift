import Foundation
import Helpers
import OpenAPIRuntime
import OpenAPIURLSession

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// A client for invoking Supabase Edge Functions.
///
/// `FunctionsClient` provides methods for calling Edge Functions deployed on your Supabase project.
/// It handles authentication token injection, region routing, and response decoding.
///
/// ## Basic usage
///
/// ```swift
/// let client = FunctionsClient(
///   url: URL(string: "https://<project-ref>.supabase.co/functions/v1")!,
///   headers: ["Authorization": "Bearer <anon-key>"]
/// )
///
/// // Invoke a function and decode the JSON response
/// let (result, _) = try await client.invokeDecodable("my-function", as: MyResponse.self)
///
/// // Invoke a function and handle raw data
/// let (data, response) = try await client.invoke("my-function") {
///   $0.method = .post
///   $0.body = try! JSONEncoder().encode(myPayload)
///   $0.headers["Content-Type"] = "application/json"
/// }
/// ```
///
/// When used via ``SupabaseClient``, authentication tokens are automatically refreshed and injected
/// into every request. You do not need to manage ``setAuth(token:)`` manually in that case.
///
/// ## Spike limitations
///
/// The generated client is POST-only. `FunctionInvokeOptions.method` and
/// `FunctionInvokeOptions.query` are accepted by the API for future compatibility but are not
/// forwarded to the server in this spike implementation. The Smithy model needs to be extended
/// to support custom HTTP methods and query parameters.
///
/// The `HTTPURLResponse` returned by `invoke` is fabricated (status code only, no headers),
/// because the generated `ClientMiddleware` layer does not yet expose per-request response headers
/// to the caller. This is a known limitation.
public actor FunctionsClient {
  /// The maximum time an Edge Function may be idle before the gateway returns a 504.
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL used to build per-function request URLs.
  public let url: URL

  /// The default region in which functions are invoked.
  public let region: FunctionRegion?

  /// The JSON decoder used to decode response bodies in ``invokeDecodable(_:as:decoder:options:)``.
  public let decoder: JSONDecoder

  /// The HTTP headers sent with every request.
  public private(set) var headers: [String: String] = [:]

  private let generatedClient: Client

  /// Creates a `FunctionsClient` for standalone use (without a ``SupabaseClient``).
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    session: URLSession = URLSession(configuration: .default),
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region,
      session: session,
      decoder: decoder,
      tokenProvider: nil
    )
  }

  package init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    session: URLSession = URLSession(configuration: .default),
    decoder: JSONDecoder = JSONDecoder(),
    tokenProvider: TokenProvider?
  ) {
    self.url = url
    self.region = region
    self.decoder = decoder
    session.configuration.timeoutIntervalForRequest = Self.requestIdleTimeout
    let transport = URLSessionTransport(configuration: .init(session: session))
    let middleware = SupabaseMiddleware(headers: headers, tokenProvider: tokenProvider)
    generatedClient = Client(
      serverURL: url,
      transport: transport,
      middlewares: [middleware, RelayErrorMiddleware()]
    )
    self.headers = headers
    if self.headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
  }

  /// Creates a `FunctionsClient` backed by a custom transport (e.g. `MockTransport` in tests).
  package init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    transport: any ClientTransport,
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.url = url
    self.region = region
    self.decoder = decoder
    self.generatedClient = Client(serverURL: url, transport: transport)
    self.headers = headers
    if self.headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
  }

  /// Updates the `Authorization` header used for subsequent requests.
  public func setAuth(token: String?) {
    if let token {
      headers["Authorization"] = "Bearer \(token)"
    } else {
      headers.removeValue(forKey: "Authorization")
    }
  }

  /// Invokes a function and decodes the JSON response body into the inferred `Decodable` type.
  public func invokeDecodable<T: Decodable>(
    _ functionName: String,
    as _: T.Type = T.self,
    decoder: JSONDecoder? = nil,
    options applyOptions: sending (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (T, HTTPURLResponse) {
    let (data, response) = try await invoke(functionName, options: applyOptions)
    return (
      try (decoder ?? self.decoder).decode(T.self, from: data),
      response
    )
  }

  /// Invokes a function and returns the raw response body and a fabricated `HTTPURLResponse`.
  ///
  /// - Note: The returned `HTTPURLResponse` carries the HTTP status code only. Response headers
  ///   are not yet available through the generated client.
  @discardableResult
  public func invoke(
    _ functionName: String,
    options applyOptions: sending (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (Data, HTTPURLResponse) {
    var options = FunctionInvokeOptions()
    applyOptions(&options)

    let input = Operations.InvokeFunction.Input(
      path: .init(functionName: functionName),
      headers: .init(x_hyphen_region: (options.region ?? region)?.rawValue),
      body: options.body.map { .binary(HTTPBody($0)) }
    )

    let output = try await generatedClient.InvokeFunction(input)

    switch output {
    case .ok(let response):
      let httpBody = try response.body.binary
      let data = try await Data(collecting: httpBody, upTo: .max)
      return (data, fabricatedResponse(functionName: functionName, statusCode: 200))

    case .badRequest(let response):
      let data: Data
      switch response.body {
      case .json(let body):
        data = (try? JSONEncoder().encode(body)) ?? Data()
      }
      throw FunctionsError.httpError(code: 400, data: data)

    case .undocumented(let statusCode, let payload):
      let data: Data
      if let body = payload.body {
        data = try await Data(collecting: body, upTo: .max)
      } else {
        data = Data()
      }
      if statusCode >= 200 && statusCode < 300 {
        return (data, fabricatedResponse(functionName: functionName, statusCode: statusCode))
      }
      throw FunctionsError.httpError(code: statusCode, data: data)
    }
  }

  #if canImport(Darwin)
    /// Invokes a function and returns an async byte stream for the response body.
    ///
    /// The stream is backed directly by the `HTTPBody` from the generated client — bytes are
    /// yielded chunk-by-chunk as they arrive from the server without any intermediate buffering.
    ///
    /// - Note: The returned `HTTPURLResponse` carries the HTTP status code only.
    @available(macOS 12.0, *)
    public func invokeStream(
      _ functionName: String,
      options applyOptions: sending (inout FunctionInvokeOptions) -> Void = { _ in }
    ) async throws -> (AsyncThrowingStream<UInt8, any Error>, HTTPURLResponse) {
      var options = FunctionInvokeOptions()
      applyOptions(&options)

      let input = Operations.InvokeFunction.Input(
        path: .init(functionName: functionName),
        headers: .init(x_hyphen_region: (options.region ?? region)?.rawValue),
        body: options.body.map { .binary(HTTPBody($0)) }
      )

      let output = try await generatedClient.InvokeFunction(input)

      switch output {
      case .ok(let response):
        // Bridge HTTPBody (AsyncSequence<ArraySlice<UInt8>>) to AsyncThrowingStream<UInt8>.
        // Bytes are forwarded chunk-by-chunk without intermediate buffering.
        let httpBody = try response.body.binary
        let stream = AsyncThrowingStream<UInt8, any Error> { continuation in
          Task {
            do {
              for try await chunk in httpBody {
                for byte in chunk {
                  continuation.yield(byte)
                }
              }
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
        }
        return (stream, fabricatedResponse(functionName: functionName, statusCode: 200))

      case .badRequest(let response):
        let data: Data
        switch response.body {
        case .json(let body):
          data = (try? JSONEncoder().encode(body)) ?? Data()
        }
        throw FunctionsError.httpError(code: 400, data: data)

      case .undocumented(let statusCode, let payload):
        let data: Data
        if let body = payload.body {
          data = try await Data(collecting: body, upTo: .max)
        } else {
          data = Data()
        }
        throw FunctionsError.httpError(code: statusCode, data: data)
      }
    }
  #endif

  // MARK: - Private

  private func fabricatedResponse(functionName: String, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
      url: url.appendingPathComponent(functionName),
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
  }
}
