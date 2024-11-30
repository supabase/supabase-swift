import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Helpers

public typealias PostgrestError = Helpers.PostgrestError
public typealias HTTPError = Helpers.HTTPError
public typealias AnyJSON = Helpers.AnyJSON

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// PostgREST client.
public final class PostgrestClient: Sendable {
  public typealias FetchHandler = @Sendable (
    _ request: HTTPRequest,
    _ bodyData: Data?
  ) async throws -> (Data, HTTPResponse)

  /// The configuration struct for the PostgREST client.
  public struct Configuration: Sendable {
    public var url: URL
    public var schema: String?
    public var headers: HTTPFields
    public var fetch: FetchHandler
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder

    let logger: (any SupabaseLogger)?

    /// Creates a PostgREST client.
    /// - Parameters:
    ///   - url: URL of the PostgREST endpoint.
    ///   - schema: Postgres schema to switch to.
    ///   - headers: Custom headers.
    ///   - logger: The logger to use.
    ///   - fetch: Custom fetch.
    ///   - encoder: The JSONEncoder to use for encoding.
    ///   - decoder: The JSONDecoder to use for decoding.
    public init(
      url: URL,
      schema: String? = nil,
      headers: HTTPFields = [:],
      logger: (any SupabaseLogger)? = nil,
      fetch: @escaping FetchHandler = { request, bodyData in
        if let bodyData {
          return try await URLSession.shared.upload(for: request, from: bodyData)
        } else {
          return try await URLSession.shared.data(for: request)
        }
      },
      encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
    ) {
      self.url = url
      self.schema = schema
      self.headers = headers
      self.logger = logger
      self.fetch = fetch
      self.encoder = encoder
      self.decoder = decoder
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
  ///   - fetch: Custom fetch.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  public convenience init(
    url: URL,
    schema: String? = nil,
    headers: HTTPFields = [:],
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { request, bodyData in
      if let bodyData {
        try await URLSession.shared.upload(for: request, from: bodyData)
      } else {
        try await URLSession.shared.data(for: request)
      }
    },
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        schema: schema,
        headers: headers,
        logger: logger,
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
      _configuration.withValue { $0.headers[.authorization] = "Bearer \(token)" }
    } else {
      _configuration.withValue { $0.headers[.authorization] = nil }
    }
    return self
  }

  /// Perform a query on a table or a view.
  /// - Parameter table: The table or view name to query.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    PostgrestQueryBuilder(
      configuration: configuration,
      request: .init(
        method: .get,
        url: configuration.url.appendingPathComponent(table),
        headerFields: configuration.headers
      ),
      bodyData: nil
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
          message: "Params should be a key-value type when using `GET` or `HEAD` options.")
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
      method: method,
      url: url,
      headerFields: configuration.headers
    )

    if let count {
      request.headerFields[.prefer] = "count=\(count.rawValue)"
    }

    return PostgrestFilterBuilder(
      configuration: configuration,
      request: request,
      bodyData: params is NoParams ? nil : body
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
