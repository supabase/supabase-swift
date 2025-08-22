import Alamofire
import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// An actor representing a client for invoking functions.
public final class FunctionsClient: Sendable {

  /// Request idle timeout: 150s (If an Edge Function doesn't send a response before the timeout, 504 Gateway Timeout will be returned)
  ///
  /// See more: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  struct MutableState {
    /// Headers to be included in the requests.
    var headers = HTTPHeaders()
  }

  private let session: Alamofire.Session
  private let mutableState = LockIsolated(MutableState())

  var headers: HTTPHeaders {
    mutableState.headers
  }

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in the requests. (Default: empty dictionary)
  ///   - region: The Region to invoke the functions in.
  ///   - logger: SupabaseLogger instance to use.
  ///   - session: The Alamofire session to use for requests. (Default: Alamofire.Session.default)
  @_disfavoredOverload
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    session: Alamofire.Session = .default
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region,
      session: session
    )
  }

  init(
    url: URL,
    headers: [String: String],
    region: String?,
    session: Alamofire.Session
  ) {
    self.url = url
    self.region = region
    self.session = session

    mutableState.withValue {
      $0.headers = HTTPHeaders(headers)
      if $0.headers["X-Client-Info"] == nil {
        $0.headers["X-Client-Info"] = "functions-swift/\(version)"
      }
    }
  }

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in the requests. (Default: empty dictionary)
  ///   - region: The Region to invoke the functions in.
  ///   - logger: SupabaseLogger instance to use.
  ///   - session: The Alamofire session to use for requests. (Default: Alamofire.Session.default)
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil,
    session: Alamofire.Session = .default
  ) {
    self.init(url: url, headers: headers, region: region?.rawValue, session: session)
  }

  /// Updates the authorization header.
  ///
  /// - Parameter token: The new JWT token sent in the authorization header.
  public func setAuth(token: String?) {
    mutableState.withValue {
      if let token {
        $0.headers["Authorization"] = "Bearer \(token)"
      } else {
        $0.headers["Authorization"] = nil
      }
    }
  }

  /// Invokes a function and decodes the response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  ///   - decode: A closure to decode the response data and HTTPURLResponse into a `Response`
  /// object.
  /// - Returns: The decoded `Response` object.
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws -> Response {
    let data = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )

    // Create a mock HTTPURLResponse for backward compatibility
    // This is a temporary solution until we can update the decode closure signature
    let mockResponse = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!

    return try decode(data, mockResponse)
  }

  /// Invokes a function and decodes the response as a specific type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  ///   - decoder: The JSON decoder to use for decoding the response. (Default: `JSONDecoder()`)
  /// - Returns: The decoded object of type `T`.
  public func invoke<T: Decodable & Sendable>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decoder: JSONDecoder = JSONDecoder()
  ) async throws -> T {
    let data = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )
    return try decoder.decode(T.self, from: data)
  }

  /// Invokes a function without expecting a response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  public func invoke(
    _ functionName: String,
    options: FunctionInvokeOptions = .init()
  ) async throws {
    _ = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )
  }

  private func rawInvoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> Data {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    return try await session.request(request)
      .validate(self.validate)
      .serializingData()
      .value
  }

  /// Invokes a function with streamed response.
  ///
  /// Function MUST return a `text/event-stream` content type for this method to work.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - invokeOptions: Options for invoking the function.
  /// - Returns: A stream of Data.
  public func invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> AsyncThrowingStream<Data, any Error> {
    let urlRequest = buildRequest(functionName: functionName, options: invokeOptions)

    let stream = session.streamRequest(urlRequest)
      .validate { request, response in
        self.validate(request: request, response: response, data: nil)
      }
      .streamTask()
      .streamingData()
      .compactMap {
        switch $0.event {
        case let .stream(.success(data)): return data
        case .complete(let completion):
          if let error = completion.error {
            throw error
          }
          return nil
        }
      }

    return AsyncThrowingStream(UncheckedSendable(stream))
  }

  private func buildRequest(functionName: String, options: FunctionInvokeOptions) -> URLRequest {
    var headers = headers
    options.headers.forEach {
      headers[$0.name] = $0.value
    }

    if let region = options.region ?? region {
      headers["X-Region"] = region
    }

    var request = URLRequest(
      url: url.appendingPathComponent(functionName).appendingQueryItems(options.query)
    )
    request.httpMethod = FunctionInvokeOptions.httpMethod(options.method)?.rawValue ?? "POST"
    request.headers = headers
    request.httpBody = options.body
    request.timeoutInterval = FunctionsClient.requestIdleTimeout

    return request
  }

  @Sendable
  private func validate(
    request: URLRequest?,
    response: HTTPURLResponse,
    data: Data?
  ) -> DataRequest.ValidationResult {
    guard 200..<300 ~= response.statusCode else {
      return .failure(FunctionsError.httpError(code: response.statusCode, data: data ?? Data()))
    }

    let isRelayError = response.headers["X-Relay-Error"] == "true"
    if isRelayError {
      return .failure(FunctionsError.relayError)
    }

    return .success(())
  }
}
