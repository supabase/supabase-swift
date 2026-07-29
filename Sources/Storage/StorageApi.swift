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
    let decoder = configuration.decoder
    openAPIClient = Client(
      serverURL: configuration.url,
      configuration: OpenAPIRuntime.Configuration(jsonEncodingOptions: [.sortedKeys]),
      transport: StorageOpenAPITransport(execute: { request in
        try await Self.executeRequest(
          request, headers: mutableStateRef.headers, http: httpRef, decoder: decoder)
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

  private static func executeRequest(
    _ request: Helpers.HTTPRequest,
    headers: [String: String],
    http: any HTTPClientType,
    decoder: JSONDecoder
  ) async throws -> Helpers.HTTPResponse {
    var request = request
    request.headers = HTTPFields(headers).merging(with: request.headers)

    let response = try await http.send(request)

    guard (200..<300).contains(response.statusCode) else {
      if let error = try? decoder.decode(StorageError.self, from: response.data) {
        throw error
      }
      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }

    return response
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
