public import Foundation
public import Helpers

extension FunctionsClient {

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region string to invoke functions in.
  ///   - logger: A logger for request and response diagnostics.
  ///   - fetch: A custom fetch handler. Defaults to `URLSession.shared`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  @_disfavoredOverload
  @available(
    *, deprecated, message: "Use init(url:options:) with a FunctionsClientOptions instead."
  )
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
      options: FunctionsClientOptions(
        headers: headers, region: region, logger: logger, decoder: decoder, session: .shared),
      transport: FetchHandlerTransport(fetch: fetch)
    )
  }

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region to invoke functions in.
  ///   - logger: A logger for request and response diagnostics.
  ///   - fetch: A custom fetch handler. Defaults to `URLSession.shared`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  @available(
    *, deprecated, message: "Use init(url:options:) with a FunctionsClientOptions instead."
  )
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
      options: FunctionsClientOptions(
        headers: headers, region: region?.rawValue, logger: logger, decoder: decoder,
        session: .shared),
      transport: FetchHandlerTransport(fetch: fetch)
    )
  }
}
