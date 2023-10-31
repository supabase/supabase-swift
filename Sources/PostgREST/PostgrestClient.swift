import Foundation
@_spi(Internal) import _Helpers

let version = _Helpers.version

/// PostgREST client.
public actor PostgrestClient {
  public typealias FetchHandler = @Sendable (_ request: URLRequest) async throws -> (
    Data, URLResponse
  )

  /// The configuration struct for the PostgREST client.
  public struct Configuration {
    public var url: URL
    public var schema: String?
    public var headers: [String: String]
    public var fetch: FetchHandler
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder

    /// Initializes a new configuration for the PostgREST client.
    /// - Parameters:
    ///   - url: The URL of the PostgREST server.
    ///   - schema: The schema to use.
    ///   - headers: The headers to include in requests.
    ///   - fetch: The fetch handler to use for requests.
    ///   - encoder: The JSONEncoder to use for encoding.
    ///   - decoder: The JSONDecoder to use for decoding.
    public init(
      url: URL,
      schema: String? = nil,
      headers: [String: String] = [:],
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
      encoder: JSONEncoder = .postgrest,
      decoder: JSONDecoder = .postgrest
    ) {
      self.url = url
      self.schema = schema
      self.headers = headers
      self.fetch = fetch
      self.encoder = encoder
      self.decoder = decoder
    }
  }

  public private(set) var configuration: Configuration

  /// Creates a PostgREST client with the specified configuration.
  /// - Parameter configuration: The configuration for the client.
  public init(configuration: Configuration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "postgrest-swift/\(version)"
    }
    self.configuration = configuration
  }

  /// Creates a PostgREST client with the specified parameters.
  /// - Parameters:
  ///   - url: The URL of the PostgREST server.
  ///   - schema: The schema to use.
  ///   - headers: The headers to include in requests.
  ///   - session: The URLSession to use for requests.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  public init(
    url: URL,
    schema: String? = nil,
    headers: [String: String] = [:],
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    encoder: JSONEncoder = .postgrest,
    decoder: JSONDecoder = .postgrest
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        schema: schema,
        headers: headers,
        fetch: fetch,
        encoder: encoder,
        decoder: decoder
      )
    )
  }

  /// Sets the authorization token for the client.
  /// - Parameter token: The authorization token.
  /// - Returns: The PostgrestClient instance.
  @discardableResult
  public func setAuth(_ token: String?) -> PostgrestClient {
    if let token {
      configuration.headers["Authorization"] = "Bearer \(token)"
    } else {
      configuration.headers.removeValue(forKey: "Authorization")
    }
    return self
  }

  /// Performs a query on a table or a view.
  /// - Parameter table: The table or view name to query.
  /// - Returns: A PostgrestQueryBuilder instance.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    PostgrestQueryBuilder(
      configuration: configuration,
      url: configuration.url.appendingPathComponent(table),
      queryParams: [],
      headers: configuration.headers,
      method: "GET",
      body: nil
    )
  }

  /// Performs a function call.
  /// - Parameters:
  ///   - fn: The function name to call.
  ///   - params: The parameters to pass to the function call.
  ///   - count: Count algorithm to use to count rows returned by the function.
  ///             Only applicable for set-returning functions.
  /// - Returns: A PostgrestTransformBuilder instance.
  /// - Throws: An error if the function call fails.
  public func rpc(
    fn: String,
    params: some Encodable,
    count: CountOption? = nil
  ) throws -> PostgrestTransformBuilder {
    try PostgrestRpcBuilder(
      configuration: configuration,
      url: configuration.url.appendingPathComponent("rpc").appendingPathComponent(fn),
      queryParams: [],
      headers: configuration.headers,
      method: "POST",
      body: nil
    ).rpc(params: params, count: count)
  }

  /// Performs a function call.
  /// - Parameters:
  ///   - fn: The function name to call.
  ///   - count: Count algorithm to use to count rows returned by the function.
  ///            Only applicable for set-returning functions.
  /// - Returns: A PostgrestTransformBuilder instance.
  /// - Throws: An error if the function call fails.
  public func rpc(
    fn: String,
    count: CountOption? = nil
  ) throws -> PostgrestTransformBuilder {
    try rpc(fn: fn, params: NoParams(), count: count)
  }
}

private let supportedDateFormatters: [ISO8601DateFormatter] = [
  { () -> ISO8601DateFormatter in
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }(),
  { () -> ISO8601DateFormatter in
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }(),
]

extension JSONDecoder {
  /// The JSONDecoder instance for PostgREST responses.
  public static let postgrest = { () -> JSONDecoder in
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      for formatter in supportedDateFormatters {
        if let date = formatter.date(from: string) {
          return date
        }
      }

      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid date format: \(string)"
      )
    }
    return decoder
  }()
}

extension JSONEncoder {
  /// The JSONEncoder instance for PostgREST requests.
  public static let postgrest = { () -> JSONEncoder in
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}
