import ConcurrencyExtras
import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Base class for Storage API operations.
///
/// ``StorageApi`` holds the ``StorageClientConfiguration`` and manages mutable per-instance HTTP
/// headers behind a lock. Both ``StorageBucketApi`` and ``StorageFileApi`` inherit from this class.
///
/// > Note: This class is `@unchecked Sendable` because all mutable state is protected by
/// > `LockIsolated`. The ``configuration`` property is immutable (`let`), while mutable headers are
/// > managed separately.
///
/// ## Topics
///
/// ### Configuration
///
/// - ``configuration``
/// - ``init(configuration:)``
///
/// ### Customizing headers
///
/// - ``setHeader(_:forKey:)``
public class StorageApi: @unchecked Sendable {
  /// The configuration used to initialize this client instance.
  public let configuration: StorageClientConfiguration

  /// The generated OpenAPI client for the Storage HTTP API. Internal implementation detail —
  /// ``StorageBucketApi``/``StorageFileApi`` use this instead of hand-building requests.
  let openAPIClient: Client

  private struct MutableState {
    var headers: [String: String]
  }

  private let mutableState: LockIsolated<MutableState>
  private let http: any HTTPClientType

  /// Extra headers for a single OpenAPI-routed call, e.g. `x-upsert`/`Duplex`/`options.headers`
  /// for `upload`/`update`. The generated `Client`'s per-operation `Input.headers` only exposes
  /// `accept`, so there's no way to pass one-off headers through its typed API; this task-local is
  /// read by the transport's `execute` closure and merged on top of the per-instance headers for
  /// the duration of the call. Scope it tightly with `withValue` around a single request.
  @TaskLocal
  static var extraHeadersForCurrentRequest: HTTPFields = [:]

  /// Creates a ``StorageApi`` with the given configuration.
  ///
  /// Subclasses call this initializer via `super.init(configuration:)`.
  ///
  /// - Parameter configuration: The configuration that controls the endpoint URL, authentication
  ///   headers, JSON codecs, and HTTP session.
  public init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }

    // if legacy uri is used, replace with new storage host (disables request buffering to allow > 50GB uploads)
    // "project-ref.supabase.co" becomes "project-ref.storage.supabase.co"
    if configuration.useNewHostname == true {
      guard
        var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false),
        let host = components.host
      else {
        fatalError("Client initialized with invalid URL: \(configuration.url)")
      }

      let regex = try! NSRegularExpression(pattern: "supabase.(co|in|red)$")

      let isSupabaseHost =
        regex.firstMatch(in: host, range: NSRange(location: 0, length: host.utf16.count)) != nil

      if isSupabaseHost, !host.contains("storage.supabase.") {
        components.host = host.replacingOccurrences(of: "supabase.", with: "storage.supabase.")
      }

      configuration.url = components.url!
    }

    let initialHeaders = configuration.headers
    self.configuration = configuration
    self.mutableState = LockIsolated(MutableState(headers: initialHeaders))

    var interceptors: [any HTTPClientInterceptor] = []
    if let logger = configuration.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    http = HTTPClient(
      fetch: configuration.session.fetch,
      interceptors: interceptors
    )

    let mutableStateRef = mutableState
    let httpRef = http

    var openAPIConfiguration = OpenAPIRuntime.Configuration(jsonEncodingOptions: [.sortedKeys])
    #if DEBUG
      if let boundary = testingBoundary.value {
        openAPIConfiguration.multipartBoundaryGenerator = ConstantMultipartBoundaryGenerator(
          boundary: boundary)
      }
    #endif

    openAPIClient = Client(
      serverURL: configuration.url,
      configuration: openAPIConfiguration,
      transport: StorageOpenAPITransport(execute: { request in
        var request = request
        request.headers = request.headers.merging(with: Self.extraHeadersForCurrentRequest)
        return try await Self.executeRequestWithoutStatusCheck(
          request, headers: mutableStateRef.headers, http: httpRef)
      })
    )
  }

  /// Sets an HTTP header that will be included in all subsequent requests made by this instance.
  ///
  /// This method is thread-safe. The header key is normalized to lowercase before being stored.
  ///
  /// ```swift
  /// storage.from("avatars")
  ///   .setHeader("x-custom-header", forKey: "X-Custom-Header")
  /// ```
  ///
  /// - Parameters:
  ///   - value: The value of the header field.
  ///   - key: The name of the header field. The key is case-insensitively stored as lowercase.
  /// - Returns: `self`, enabling method chaining.
  @discardableResult
  public func setHeader(_ value: String, forKey key: String) -> Self {
    mutableState.withValue { $0.headers[key.lowercased()] = value }
    return self
  }

  /// Merges the instance's stored headers into `request` without inspecting the response status.
  ///
  /// Shared by ``executeRequest(_:headers:http:decoder:)`` (which additionally throws on non-2xx
  /// responses) and ``executeRequestWithoutStatusCheck(_:headers:http:)`` (used by the OpenAPI
  /// transport, which must return the raw response so the facade can decode the real error body
  /// from the generated `Output` type instead of a generic ``StorageError``).
  private static func send(
    _ request: Helpers.HTTPRequest,
    headers: [String: String],
    http: any HTTPClientType
  ) async throws -> Helpers.HTTPResponse {
    var request = request
    request.headers = HTTPFields(headers).merging(with: request.headers)
    return try await http.send(request)
  }

  private static func executeRequest(
    _ request: Helpers.HTTPRequest,
    headers: [String: String],
    http: any HTTPClientType,
    decoder: JSONDecoder
  ) async throws -> Helpers.HTTPResponse {
    let response = try await send(request, headers: headers, http: http)

    guard (200..<300).contains(response.statusCode) else {
      if let error = try? decoder.decode(StorageError.self, from: response.data) {
        throw error
      }
      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }

    return response
  }

  /// Same request pipeline as ``executeRequest(_:headers:http:decoder:)`` but does not throw on
  /// non-2xx responses. Used for the OpenAPI transport path, which must return the raw response so
  /// error mapping happens in the generated-`Output`-aware facade methods instead.
  private static func executeRequestWithoutStatusCheck(
    _ request: Helpers.HTTPRequest,
    headers: [String: String],
    http: any HTTPClientType
  ) async throws -> Helpers.HTTPResponse {
    try await send(request, headers: headers, http: http)
  }

  @discardableResult
  func execute(_ request: Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse {
    try await Self.executeRequest(
      request, headers: mutableState.headers, http: http, decoder: configuration.decoder)
  }
}

extension Helpers.HTTPRequest {
  init(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem],
    formData: MultipartFormData,
    options: FileOptions,
    headers: HTTPFields = [:]
  ) throws {
    var headers = headers
    if headers[.contentType] == nil {
      headers[.contentType] = formData.contentType
    }
    if headers[.cacheControl] == nil {
      headers[.cacheControl] = "max-age=\(options.cacheControl)"
    }
    try self.init(
      url: url,
      method: method,
      query: query,
      headers: headers,
      body: formData.encode()
    )
  }
}
