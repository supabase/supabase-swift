public import Foundation
import HTTPTypes
public import Helpers
public import Logging

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// The main entry point for interacting with a PostgREST server.
///
/// ``PostgrestClient`` lets you query and mutate data exposed by PostgREST. Start by calling
/// ``from(_:)->PostgrestQueryBuilder`` to target a table or view, or ``rpc(_:params:head:get:count:)`` to invoke a
/// stored function.
///
/// ```swift
/// let client = PostgrestClient(
///   url: URL(string: "https://<project>.supabase.co/rest/v1")!,
///   headers: ["apikey": "<anon-key>"]
/// )
///
/// // SELECT * FROM todos
/// let todos: [Todo] = try await client
///   .from("todos")
///   .select()
///   .execute()
///   .value
/// ```
///
/// ## Topics
///
/// ### Creating a Client
///
/// - ``init(configuration:)``
/// - ``init(url:schema:headers:logger:http:encoder:decoder:retryEnabled:accessToken:)``
/// - ``Configuration``
///
/// ### Querying and Mutating Data
///
/// - ``from(_:)->PostgrestQueryBuilder``
/// - ``rpc(_:params:head:get:count:)``
/// - ``rpc(_:head:get:count:)``
///
/// ### Switching the Schema
///
/// - ``schema(_:)``
///
/// ### Inspecting Configuration
///
/// - ``configuration``
public struct PostgrestClient: Sendable {
  /// Configuration options for a ``PostgrestClient`` instance.
  ///
  /// Create a ``Configuration`` value and pass it to ``PostgrestClient/init(configuration:)`` when
  /// you need fine-grained control over the client, such as supplying a custom ``http`` transport
  /// or middleware chain, or a custom ``jsonEncoder``/``jsonDecoder``.
  ///
  /// ## Topics
  ///
  /// ### Creating Configuration
  ///
  /// - ``init(url:schema:headers:logger:http:encoder:decoder:retryEnabled:accessToken:)``
  ///
  /// ### Configuration Properties
  ///
  /// - ``url``
  /// - ``schema``
  /// - ``headers``
  /// - ``http``
  /// - ``encoder``
  /// - ``decoder``
  /// - ``retryEnabled``
  /// - ``accessToken``
  ///
  /// ### Defaults
  ///
  /// - ``jsonEncoder``
  /// - ``jsonDecoder``
  /// - ``defaultHeaders``
  public struct Configuration: Sendable {
    /// The base URL of the PostgREST endpoint.
    public var url: URL

    /// The PostgreSQL schema to query, or `nil` to use the PostgREST default (`public`).
    public var schema: String?

    /// Additional HTTP headers sent with every request.
    public var headers: [String: String]

    /// The transport and middleware chain every request goes through.
    public var http: HTTPClientConfiguration

    /// The `JSONEncoder` used to serialize request bodies.
    ///
    /// Defaults to ``jsonEncoder``, which is pre-configured with Supabase-compatible settings.
    /// Individual calls to ``PostgrestRequestBuilder/insert(_:returning:count:encoder:)``,
    /// ``PostgrestRequestBuilder/update(_:returning:count:encoder:)``, and
    /// ``PostgrestRequestBuilder/upsert(_:onConflict:returning:count:ignoreDuplicates:encoder:)``
    /// can override this per call.
    public let encoder: JSONEncoder

    /// The `JSONDecoder` used to deserialize response bodies.
    ///
    /// Defaults to ``jsonDecoder``, which is pre-configured with Supabase-compatible settings.
    /// Individual calls to ``PostgrestRequestBuilder/execute(options:decoder:)``
    /// can override this per call. Never used to decode ``PostgrestError/ServerError`` — that
    /// always uses a fixed internal decoder, decoupled from this setting.
    public let decoder: JSONDecoder

    /// Whether the client should automatically retry transient errors.
    ///
    /// When `true` (the default), GET and HEAD requests that receive an HTTP 503 or 520
    /// response, or encounter a network error, are retried up to three times with jittered
    /// exponential back-off. Set to `false` to disable retries globally; individual requests
    /// can also override this via ``PostgrestRequestBuilder/retry(enabled:)``.
    public var retryEnabled: Bool

    /// The one retry rule PostgREST applies when ``retryEnabled`` is `true`, mirroring
    /// postgrest-js. Fixed on purpose: only GET and HEAD are replayed, and only a 503 or a
    /// Cloudflare 520 counts as transient — both mean the schema cache or the edge is
    /// reloading. Every other status is a real answer from the database and is never retried.
    static let retryPolicy = RetryPolicy(
      maxAttempts: 4,
      baseDelay: .seconds(1),
      maxDelay: .seconds(30),
      retryableStatuses: [503, 520],
      retryableMethods: [.get, .head]
    )

    /// An async closure returning the current access token, resolved fresh for every request and
    /// sent as `Authorization: Bearer <token>`. `nil` (the default) sends no bearer token from this
    /// closure. An `Authorization` header already present on the request — from `headers` above, or
    /// from an explicit `PostgrestRequestBuilder.setHeader("Authorization", ...)` call — always
    /// takes precedence over this closure's result.
    public var accessToken: (@Sendable () async throws -> String?)?

    let logger: Logging.Logger

    /// Creates a new ``Configuration``.
    ///
    /// - Parameters:
    ///   - url: The base URL of the PostgREST endpoint.
    ///   - schema: The PostgreSQL schema to use. Defaults to `nil` (PostgREST default).
    ///   - headers: Additional HTTP headers sent with every request.
    ///   - logger: A logger for diagnostic output. Defaults to a build-config-aware logger.
    ///   - http: The transport and middleware chain every request goes through.
    ///   - encoder: The `JSONEncoder` used for request bodies. Defaults to ``jsonEncoder``.
    ///   - decoder: The `JSONDecoder` used for response bodies. Defaults to ``jsonDecoder``.
    ///   - retryEnabled: Whether to retry transient errors. Defaults to `true`.
    ///   - accessToken: An async closure returning the current access token. Defaults to `nil`.
    public init(
      url: URL,
      schema: String? = nil,
      headers: [String: String] = [:],
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.postgrest"),
      http: HTTPClientConfiguration = .init(),
      encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder,
      retryEnabled: Bool = true,
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.url = url
      self.schema = schema
      self.headers = headers
      var logger = logger
      logger[metadataKey: "system"] = "postgrest"
      self.logger = logger
      self.http = http
      self.encoder = encoder
      self.decoder = decoder
      self.retryEnabled = retryEnabled
      self.accessToken = accessToken
    }
  }

  /// The configuration this client was created with.
  public let configuration: Configuration
  let clock: any Clock<Duration>

  /// Creates a ``PostgrestClient`` from an existing ``Configuration``.
  ///
  /// - Parameter configuration: The configuration to use.
  public init(configuration: Configuration) {
    self.init(configuration: configuration, clock: ContinuousClock())
  }

  init(configuration: Configuration, clock: any Clock<Duration>) {
    var configuration = configuration
    configuration.headers.merge(Configuration.defaultHeaders) { l, _ in l }
    self.configuration = configuration
    self.clock = clock
  }

  /// Creates a ``PostgrestClient`` with individual configuration parameters.
  ///
  /// This is a convenience initializer that constructs a ``Configuration`` internally.
  /// Use ``init(configuration:)`` when you need to share or reuse a configuration value.
  ///
  /// - Parameters:
  ///   - url: The base URL of the PostgREST endpoint.
  ///   - schema: The PostgreSQL schema to use. Defaults to `nil` (PostgREST default).
  ///   - headers: Additional HTTP headers sent with every request.
  ///   - logger: A logger for diagnostic output. Defaults to a build-config-aware logger.
  ///   - http: The transport and middleware chain every request goes through.
  ///   - encoder: The `JSONEncoder` used for request bodies. Defaults to ``Configuration/jsonEncoder``.
  ///   - decoder: The `JSONDecoder` used for response bodies. Defaults to ``Configuration/jsonDecoder``.
  ///   - retryEnabled: Whether to retry transient errors. Defaults to `true`.
  ///   - accessToken: An async closure returning the current access token. Defaults to `nil`.
  public init(
    url: URL,
    schema: String? = nil,
    headers: [String: String] = [:],
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.postgrest"),
    http: HTTPClientConfiguration = .init(),
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder,
    retryEnabled: Bool = true,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        schema: schema,
        headers: headers,
        logger: logger,
        http: http,
        encoder: encoder,
        decoder: decoder,
        retryEnabled: retryEnabled,
        accessToken: accessToken
      )
    )
  }

  /// Returns a query builder targeting the specified table or view.
  ///
  /// Call ``PostgrestRequestBuilder/select(_:head:count:)`` on the returned builder to begin a
  /// `SELECT`, or use ``PostgrestRequestBuilder/insert(_:returning:count:encoder:)``,
  /// ``PostgrestRequestBuilder/update(_:returning:count:encoder:)``,
  /// ``PostgrestRequestBuilder/upsert(_:onConflict:returning:count:ignoreDuplicates:encoder:)``, or
  /// ``PostgrestRequestBuilder/delete(returning:count:)`` for write operations.
  ///
  /// - Parameter table: The name of the table or view to query.
  /// - Returns: A ``PostgrestQueryBuilder`` for the specified table or view.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    PostgrestQueryBuilder(
      configuration: configuration,
      request: .init(
        method: .get,
        url: configuration.url.appendingPathComponent(table),
        headerFields: HTTPFields(configuration.headers)
      ),
      clock: clock
    )
  }

  /// Calls a PostgreSQL stored function (RPC) with parameters.
  ///
  /// ```swift
  /// // Call a function that accepts a parameter
  /// let result: [String] = try await client
  ///   .rpc("search_todos", params: ["keyword": "groceries"])
  ///   .execute()
  ///   .value
  /// ```
  ///
  /// - Parameters:
  ///   - fn: The name of the function to invoke.
  ///   - params: An `Encodable` value whose properties are passed as function arguments.
  ///   - head: When `true`, the response body is omitted (HEAD request). Useful for retrieving only the count.
  ///   - get: When `true`, parameters are sent as query string items and the function runs in read-only mode.
  ///   - count: The row-count algorithm to use for [set-returning functions](https://www.postgresql.org/docs/current/functions-srf.html), or `nil` to skip counting.
  /// - Returns: A ``PostgrestFilterBuilder`` that you can further filter or execute.
  /// - Throws: ``PostgrestError`` with kind `.invalidRequest` if `params` cannot be serialized to a key-value JSON object when using `head` or `get`.
  public func rpc(
    _ fn: String,
    params: some Encodable,
    head: Bool = false,
    get: Bool = false,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    let method: HTTPRequest.Method
    var url = configuration.url.appendingPathComponent("rpc/\(fn)")
    let bodyData = try configuration.encoder.encode(params)
    var body: Data?

    if head || get {
      method = head ? .head : .get

      guard case .object(let json) = try JSONValue.decoder.decode(JSONValue.self, from: bodyData)
      else {
        throw PostgrestError(
          kind: .invalidRequest,
          message: "Params should be a key-value type when using `GET` or `HEAD` options."
        )
      }

      for (key, value) in json {
        url.appendQueryItems([URLQueryItem(name: key, value: queryValue(for: value))])
      }

    } else {
      method = .post
      body = bodyData
    }

    var request = HTTPRequest(
      method: method,
      url: url,
      headerFields: HTTPFields(configuration.headers)
    )

    if let count {
      request.headerFields[.prefer] = "count=\(count.rawValue)"
    }

    return PostgrestFilterBuilder(
      configuration: configuration,
      request: request,
      body: params is NoParams ? nil : body,
      clock: clock
    )
  }

  /// Calls a PostgreSQL stored function (RPC) with no parameters.
  ///
  /// Use this overload when the function takes no arguments.
  ///
  /// ```swift
  /// let count: Int = try await client
  ///   .rpc("active_user_count")
  ///   .execute()
  ///   .value
  /// ```
  ///
  /// - Parameters:
  ///   - fn: The name of the function to invoke.
  ///   - head: When `true`, the response body is omitted (HEAD request). Useful for retrieving only the count.
  ///   - get: When `true`, the function runs in read-only mode.
  ///   - count: The row-count algorithm to use for [set-returning functions](https://www.postgresql.org/docs/current/functions-srf.html), or `nil` to skip counting.
  /// - Returns: A ``PostgrestFilterBuilder`` that you can further filter or execute.
  /// - Throws: ``PostgrestError`` with kind `.invalidRequest` if the request cannot be constructed.
  public func rpc(
    _ fn: String,
    head: Bool = false,
    get: Bool = false,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try rpc(fn, params: NoParams(), head: head, get: get, count: count)
  }

  /// Returns a new client that queries the specified PostgreSQL schema.
  ///
  /// The schema must be listed in the PostgREST `db-schemas` configuration. Calling this method
  /// does not mutate the receiver; it returns a fresh ``PostgrestClient`` with the schema applied.
  ///
  /// ```swift
  /// let privateClient = client.schema("private")
  /// let rows = try await privateClient.from("secrets").select().execute().value
  /// ```
  ///
  /// - Parameter schema: The PostgreSQL schema name.
  /// - Returns: A new ``PostgrestClient`` configured to use the given schema.
  public func schema(_ schema: String) -> PostgrestClient {
    var configuration = configuration
    configuration.schema = schema
    return PostgrestClient(configuration: configuration, clock: clock)
  }

  private func queryValue(for value: JSONValue) -> String {
    switch value {
    case .null:
      return "null"
    case .bool(let bool):
      return bool ? "true" : "false"
    case .integer(let integer):
      return String(integer)
    case .double(let double):
      return String(double)
    case .string(let string):
      return string
    case .array(let array):
      return "{\(array.map(arrayElementValue(for:)).joined(separator: ","))}"
    case .object:
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      if let data = try? encoder.encode(value),
        let json = String(data: data, encoding: .utf8)
      {
        return json
      }
      return ""
    }
  }

  /// One element of a Postgres array literal. An element that is empty, spells NULL, or holds
  /// `,` `{` `}` `"` `\` is double-quoted, as for the `cs`/`cd` filters, so it stays one element
  /// with its own text. A nested array stays a bare sub-literal, and a JSON null a bare `null`.
  private func arrayElementValue(for value: JSONValue) -> String {
    switch value {
    case .null, .array:
      return queryValue(for: value)
    case .bool, .integer, .double, .string, .object:
      return escapePostgRESTArrayLiteralElement(queryValue(for: value))
    }
  }
}

struct NoParams: Encodable {}

extension HTTPField.Name {
  static let prefer = Self("Prefer")!
}
