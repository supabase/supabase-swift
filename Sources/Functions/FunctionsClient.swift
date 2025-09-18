import Alamofire
import ConcurrencyExtras
import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// An actor representing a client for invoking functions.
public actor FunctionsClient {

  /// Request idle timeout: 150s (If an Edge Function doesn't send a response before the timeout, 504 Gateway Timeout will be returned)
  ///
  /// See more: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: FunctionRegion?

  private let session: Alamofire.Session

  private(set) public var headers: HTTPHeaders

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in the requests. (Default: empty HTTPHeaders)
  ///   - region: The Region to invoke the functions in.
  ///   - logger: SupabaseLogger instance to use.
  ///   - session: The Alamofire session to use for requests. (Default: Alamofire.Session.default)
  public init(
    url: URL,
    headers: HTTPHeaders = [],
    region: FunctionRegion? = nil,
    logger: SupabaseLogger? = nil,
    session: Alamofire.Session = .default
  ) {
    self.url = url
    self.region = region
    self.session = session

    self.headers = headers
    if self.headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
  }

  /// Updates the authorization header.
  ///
  /// - Parameter token: The new JWT token sent in the authorization header.
  public func setAuth(token: String?) {
    if let token {
      headers["Authorization"] = "Bearer \(token)"
    } else {
      headers["Authorization"] = nil
    }
  }

  /// Invokes a function and decodes the response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure to configure the options for invoking the function.
  ///   - decode: A closure to decode the response data and HTTPURLResponse into a `Response`
  /// object.
  /// - Returns: The decoded `Response` object.
  public func invoke<Response>(
    _ functionName: String,
    options: @Sendable (inout FunctionInvokeOptions) -> Void = { _ in },
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws(FunctionsError) -> Response {
    var opt = FunctionInvokeOptions()
    options(&opt)

    let dataTask = self.rawInvoke(
      functionName: functionName,
      invokeOptions: opt
    )
    .serializingData()

    guard
      let data = await dataTask.response.data,
      let response = await dataTask.response.response
    else {
      throw FunctionsError.unknown(URLError(.badServerResponse))
    }

    do {
      return try decode(data, response)
    } catch {
      throw mapToFunctionsError(error)
    }
  }

  /// Invokes a function and decodes the response as a specific type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure to configure the options for invoking the function.
  ///   - decoder: The JSON decoder to use for decoding the response. (Default: `JSONDecoder()`)
  /// - Returns: The decoded object of type `T`.
  public func invoke<T: Decodable & Sendable>(
    _ functionName: String,
    options: @Sendable (inout FunctionInvokeOptions) -> Void = { _ in },
    decoder: JSONDecoder = JSONDecoder()
  ) async throws(FunctionsError) -> T {
    var opt = FunctionInvokeOptions()
    options(&opt)

    return try await wrappingError(or: mapToFunctionsError) {
      try await self.rawInvoke(
        functionName: functionName,
        invokeOptions: opt
      )
      .serializingDecodable(T.self, decoder: decoder)
      .value
    }
  }

  /// Invokes a function without expecting a response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure to configure the options for invoking the function.
  public func invoke(
    _ functionName: String,
    options: @Sendable (inout FunctionInvokeOptions) -> Void = { _ in },
  ) async throws(FunctionsError) {
    var opt = FunctionInvokeOptions()
    options(&opt)

    _ = try await wrappingError(or: mapToFunctionsError) {
      try await self.rawInvoke(
        functionName: functionName,
        invokeOptions: opt
      )
      .serializingData()
      .value
    }
  }

  private func rawInvoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) -> DataRequest {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    return self.session.request(request).validate(self.validate)
  }

  /// Invokes a function with streamed response.
  ///
  /// Function MUST return a `text/event-stream` content type for this method to work.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure to configure the options for invoking the function.
  /// - Returns: A stream of Data.
  public func invokeWithStreamedResponse(
    _ functionName: String,
    options: @Sendable (inout FunctionInvokeOptions) -> Void = { _ in },
  ) -> AsyncThrowingStream<Data, any Error> {
    var opt = FunctionInvokeOptions()
    options(&opt)

    let urlRequest = buildRequest(functionName: functionName, options: opt)

    let stream = session.streamRequest(urlRequest)
      .validate { request, response in
        self.validate(request: request, response: response, data: nil)
      }
      .streamTask()
      .streamingData()
      .compactMap {
        switch $0.event {
        case .stream(.success(let data)): return data
        case .complete(let completion):
          if let error = completion.error {
            throw mapToFunctionsError(error)
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
      headers["X-Region"] = region.rawValue
    }

    var request = URLRequest(
      url: url.appendingPathComponent(functionName).appendingQueryItems(options.query)
    )
    request.method = options.method
    request.headers = headers
    request.httpBody = options.rawBody
    request.timeoutInterval = FunctionsClient.requestIdleTimeout

    return request
  }

  private nonisolated func validate(
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
