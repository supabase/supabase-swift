import Alamofire
import ConcurrencyExtras
import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// A client for invoking Supabase Edge Functions.
///
/// The `FunctionsClient` provides a type-safe, async/await interface for calling Supabase Edge Functions.
/// It supports various request types including JSON, binary data, file uploads, and streaming responses.
///
/// ## Basic Usage
///
/// ```swift
/// // Initialize the client
/// let functionsClient = FunctionsClient(
///   url: URL(string: "https://your-project.supabase.co/functions/v1")!,
///   headers: HTTPHeaders(["apikey": "your-anon-key"])
/// )
///
/// // Invoke a simple function
/// try await functionsClient.invoke("hello-world")
///
/// // Invoke with JSON data and get a typed response
/// struct User: Codable {
///   let name: String
///   let email: String
/// }
///
/// let user = try await functionsClient.invoke("get-user") as User
/// print("User: \(user.name)")
/// ```
///
/// ## Advanced Usage
///
/// ```swift
/// // Invoke with custom options
/// let result = try await functionsClient.invoke("process-data") { options in
///   options.method = .post
///   options.body = .encodable(["input": "data"])
///   options.headers["X-Custom-Header"] = "value"
///   options.region = .usEast1
/// }
///
/// // File upload
/// let fileURL = URL(fileURLWithPath: "/path/to/file.pdf")
/// try await functionsClient.invoke("upload-file") { options in
///   options.body = .fileURL(fileURL)
/// }
///
/// // Streaming response
/// let stream = functionsClient.invokeWithStreamedResponse("stream-data")
/// for try await data in stream {
///   print("Received: \(String(data: data, encoding: .utf8) ?? "")")
/// }
/// ```
///
/// ## Authentication
///
/// ```swift
/// // Set authentication token
/// await functionsClient.setAuth(token: "your-jwt-token")
///
/// // Clear authentication
/// await functionsClient.setAuth(token: nil)
/// ```
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

  /// Invokes a function with custom response decoding.
  ///
  /// This method allows you to provide a custom decoding closure for handling the response data.
  /// Use this when you need fine-grained control over how the response is processed.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure to configure the options for invoking the function.
  ///   - decode: A closure to decode the response data and HTTPURLResponse into a `Response` object.
  /// - Returns: The decoded `Response` object.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Custom decoding with error handling
  /// let result = try await functionsClient.invoke("get-data") { data, response in
  ///   guard response.statusCode == 200 else {
  ///     throw MyCustomError.invalidResponse
  ///   }
  ///   return try JSONDecoder().decode(MyData.self, from: data)
  /// }
  /// ```
  public func invoke<Response>(
    _ functionName: String,
    options: @Sendable (inout FunctionInvokeOptions) -> Void = { _ in },
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws(FunctionsError) -> Response {
    var opt = FunctionInvokeOptions()
    options(&opt)

    let dataTask = try self.rawInvoke(
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

  /// Invokes a function and decodes the response as a specific `Decodable` type.
  ///
  /// This is the most commonly used method for invoking functions that return JSON data.
  /// The response will be automatically decoded to the specified type using JSON decoding.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure to configure the options for invoking the function.
  ///   - decoder: The JSON decoder to use for decoding the response. (Default: `JSONDecoder()`)
  /// - Returns: The decoded object of type `T`.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// // Simple invocation with typed response
  /// struct User: Codable {
  ///   let id: String
  ///   let name: String
  ///   let email: String
  /// }
  ///
  /// let user = try await functionsClient.invoke("get-user") as User
  ///
  /// // With custom options
  /// let users = try await functionsClient.invoke("get-users") { options in
  ///   options.query = [URLQueryItem(name: "limit", value: "10")]
  /// } as [User]
  ///
  /// // With custom decoder
  /// let customDecoder = JSONDecoder()
  /// customDecoder.dateDecodingStrategy = .iso8601
  /// let data = try await functionsClient.invoke("get-data", decoder: customDecoder) as MyData
  /// ```
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
  /// Use this method when you need to trigger a function but don't need to process the response.
  /// This is commonly used for fire-and-forget operations, webhooks, or background tasks.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure to configure the options for invoking the function.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// // Simple fire-and-forget invocation
  /// try await functionsClient.invoke("send-notification")
  ///
  /// // With custom options
  /// try await functionsClient.invoke("process-webhook") { options in
  ///   options.method = .post
  ///   options.body = .encodable(["event": "user_signup"])
  ///   options.headers["X-Webhook-Source"] = "mobile-app"
  /// }
  ///
  /// // Background task with specific region
  /// try await functionsClient.invoke("cleanup-data") { options in
  ///   options.region = .usEast1
  ///   options.query = [URLQueryItem(name: "batch_size", value: "100")]
  /// }
  /// ```
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
  ) throws(FunctionsError) -> DataRequest {
    let urlRequest = try buildRequest(functionName: functionName, options: invokeOptions)

    let request =
      switch invokeOptions.body {
      case .multipartFormData(let formData):
        self.session.upload(multipartFormData: formData, with: urlRequest)
      case .fileURL(let url):
        self.session.upload(url, with: urlRequest)
      default:
        self.session.request(urlRequest)
      }

    return request.validate(self.validate)
  }

  /// Invokes a function with streamed response.
  ///
  /// This method is used for functions that return streaming data, such as Server-Sent Events (SSE)
  /// or real-time data streams. The function MUST return a `text/event-stream` content type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure to configure the options for invoking the function.
  /// - Returns: An `AsyncThrowingStream` of `Data` chunks.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// // Basic streaming
  /// let stream = functionsClient.invokeWithStreamedResponse("stream-data")
  /// for try await data in stream {
  ///   let message = String(data: data, encoding: .utf8) ?? ""
  ///   print("Received: \(message)")
  /// }
  ///
  /// // With custom options
  /// let stream = functionsClient.invokeWithStreamedResponse("chat-stream") { options in
  ///   options.body = .encodable(["room_id": "general"])
  ///   options.headers["X-User-ID"] = "user123"
  /// }
  ///
  /// // Processing streaming JSON
  /// for try await data in stream {
  ///   if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
  ///     print("JSON chunk: \(json)")
  ///   }
  /// }
  /// ```
  public func invokeWithStreamedResponse(
    _ functionName: String,
    options: @Sendable (inout FunctionInvokeOptions) -> Void = { _ in },
  ) -> AsyncThrowingStream<Data, any Error> {
    var opt = FunctionInvokeOptions()
    options(&opt)

    do {
      let urlRequest = try buildRequest(functionName: functionName, options: opt)
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
    } catch {
      return AsyncThrowingStream.finished(throwing: mapToFunctionsError(error))
    }
  }

  private func buildRequest(
    functionName: String,
    options: FunctionInvokeOptions
  ) throws(FunctionsError) -> URLRequest {
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

    switch options.body {
    case .data(let data):
      request.httpBody = data
      if request.headers["Content-Type"] == nil {
        request.headers["Content-Type"] = "application/octet-stream"
      }

    case .encodable(let encodable, let encoder):
      do {
        request = try JSONParameterEncoder(encoder: encoder ?? JSONEncoder.supabase())
          .encode(encodable, into: request)
      } catch {
        throw mapToFunctionsError(error)
      }
    case .string(let string):
      request.httpBody = string.data(using: .utf8)
      if request.headers["Content-Type"] == nil {
        request.headers["Content-Type"] = "text/plain"
      }

    case .multipartFormData, .fileURL:
      // multipartFormData and fileURL are handled by calling a different method
      break

    case nil:
      break
    }

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
