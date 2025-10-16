import Alamofire
import ConcurrencyExtras
import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// PostgREST client.
public final class PostgrestClient: Sendable {
  public typealias FetchHandler =
    @Sendable (_ request: URLRequest) async throws -> (
      Data, URLResponse
    )

  /// The configuration struct for the PostgREST client.
  public struct Configuration: Sendable {
    public var url: URL
    public var schema: String?
    public var headers: [String: String]
    public var fetch: FetchHandler
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder

    let http: any HTTPClientType
    let logger: (any SupabaseLogger)?

    /// Creates a PostgREST client.
    /// - Parameters:
    ///   - url: URL of the PostgREST endpoint.
    ///   - schema: Postgres schema to switch to.
    ///   - headers: Custom headers.
    ///   - logger: The logger to use.
    ///   - alamofireSession: Alamofire session to use for making requests.
    ///   - encoder: The JSONEncoder to use for encoding.
    ///   - decoder: The JSONDecoder to use for decoding.
    public init(
      url: URL,
      schema: String? = nil,
      headers: [String: String] = [:],
      logger: (any SupabaseLogger)? = nil,
      alamofireSession: Alamofire.Session = .default,
      encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
    ) {
      self.init(
        url: url,
        schema: schema,
        headers: headers,
        logger: logger,
        fetch: { try await alamofireSession.session.data(for: $0) },
        alamofireSession: alamofireSession,
        encoder: encoder,
        decoder: decoder
      )
    }

    init(
      url: URL,
      schema: String?,
      headers: [String: String],
      logger: (any SupabaseLogger)?,
      fetch: FetchHandler?,
      alamofireSession: Alamofire.Session,
      encoder: JSONEncoder,
      decoder: JSONDecoder
    ) {
      self.url = url
      self.schema = schema
      self.headers = headers
      self.logger = logger
      self.encoder = encoder
      self.decoder = decoder

      var interceptors: [any HTTPClientInterceptor] = []
      if let logger {
        interceptors.append(LoggerInterceptor(logger: logger))
      }

      self.http =
        if let fetch {
          HTTPClient(fetch: fetch, interceptors: interceptors)
        } else {
          AlamofireHTTPClient(session: alamofireSession)
        }

        self.fetch = fetch ?? { try await alamofireSession.session.data(for: $0) }
    }
  }

  private let _configuration: LockIsolated<Configuration>
  public var configuration: Configuration { _configuration.value }

  /// Creates a PostgREST client with the specified configuration.
  /// - Parameter configuration: The configuration for the client.
  public init(configuration: Configuration) {
    _configuration = LockIsolated(configuration)
    _configuration.withValue {
      $0.headers.merge(Configuration.defaultHeaders) { l, _ in l }
    }
  }

  /// Creates a PostgREST client with the specified parameters.
  /// - Parameters:
  ///   - url: URL of the PostgREST endpoint.
  ///   - schema: Postgres schema to switch to.
  ///   - headers: Custom headers.
  ///   - logger: The logger to use.
  ///   - alamofireSession: Alamofire session to use for making requests.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  public convenience init(
    url: URL,
    schema: String? = nil,
    headers: [String: String] = [:],
    logger: (any SupabaseLogger)? = nil,
    alamofireSession: Alamofire.Session = .default,
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        schema: schema,
        headers: headers,
        logger: logger,
        alamofireSession: alamofireSession,
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
      _configuration.withValue { $0.headers["Authorization"] = "Bearer \(token)" }
    } else {
      _ = _configuration.withValue { $0.headers.removeValue(forKey: "Authorization") }
    }
    return self
  }

  /// Perform a query on a table or a view.
  /// - Parameter table: The table or view name to query.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    PostgrestQueryBuilder(
      configuration: configuration,
      request: .init(
        url: configuration.url.appendingPathComponent(table),
        method: .get,
        headers: HTTPFields(configuration.headers)
      )
    )
  }

  /// Perform a function call.
  /// - Parameters:
  ///   - fn: The function name to call.
  ///   - params: The parameters to pass to the function call.
  ///   - head: When set to `true`, `data`, will not be returned. Useful if you only need the count.
  ///   - get: When set to `true`, the function will be called with read-only access mode.
  ///   - count: Count algorithm to use to count rows returned by the function. Only applicable for [set-returning functions](https://www.postgresql.org/docs/current/functions-srf.html).
  public func rpc(
    _ fn: String,
    params: some Encodable & Sendable,
    head: Bool = false,
    get: Bool = false,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    let method: HTTPTypes.HTTPRequest.Method
    var url = configuration.url.appendingPathComponent("rpc/\(fn)")
    let bodyData = try configuration.encoder.encode(params)
    var body: Data?

    if head || get {
      method = head ? .head : .get

      guard let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
        throw PostgrestError(
          message: "Params should be a key-value type when using `GET` or `HEAD` options."
        )
      }

      for (key, value) in json {
        let formattedValue = (value as? [Any]).map(cleanFilterArray) ?? String(describing: value)
        url.appendQueryItems([URLQueryItem(name: key, value: formattedValue)])
      }

    } else {
      method = .post
      body = bodyData
    }

    var request = HTTPRequest(
      url: url,
      method: method,
      headers: HTTPFields(configuration.headers),
      body: params is NoParams ? nil : body
    )

    if let count {
      request.headers[.prefer] = "count=\(count.rawValue)"
    }

    return PostgrestFilterBuilder(
      configuration: configuration,
      request: request
    )
  }

  /// Perform a function call.
  /// - Parameters:
  ///   - fn: The function name to call.
  ///   - head: When set to `true`, `data`, will not be returned. Useful if you only need the count.
  ///   - get: When set to `true`, the function will be called with read-only access mode.
  ///   - count: Count algorithm to use to count rows returned by the function. Only applicable for [set-returning functions](https://www.postgresql.org/docs/current/functions-srf.html).
  public func rpc(
    _ fn: String,
    head: Bool = false,
    get: Bool = false,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try rpc(fn, params: NoParams(), head: head, get: get, count: count)
  }

  /// Select a schema to query or perform an function (rpc) call.
  ///
  /// The schema needs to be on the list of exposed schemas inside Supabase.
  /// - Parameter schema: The schema to query.
  public func schema(_ schema: String) -> PostgrestClient {
    var configuration = configuration
    configuration.schema = schema
    return PostgrestClient(configuration: configuration)
  }

  private func cleanFilterArray(_ filter: [Any]) -> String {
    "{\(filter.map { String(describing: $0) }.joined(separator: ","))}"
  }
}

struct NoParams: Encodable {}

extension HTTPField.Name {
  static let prefer = Self("Prefer")!
}
