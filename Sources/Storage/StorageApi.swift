import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Internal implementation detail shared by ``SupabaseStorageClient``, ``StorageFileApi``, and the
/// Vectors trio (``StorageVectorsClient``, ``VectorBucketClient``, ``VectorIndexClient``).
///
/// Holds the ``StorageClientConfiguration`` and the underlying HTTP client used to execute
/// requests. Each of the types above holds a ``StorageApi`` value and delegates to it rather than
/// inheriting from it.
struct StorageApi: Sendable {
  /// The apex domains the storage hostname rewrite applies to, each carrying a leading dot so the
  /// match has to land on a hostname-label boundary.
  ///
  /// Without the dot, any host merely *ending* in the apex matches: a caller-owned domain like
  /// `not-supabase.co` would be rewritten to `not-storage.supabase.co`, pointing requests at a
  /// domain the caller does not control. The bare apex `supabase.co` is excluded for the same
  /// reason — it is not a project host.
  private static let legacySupabaseHostSuffixes = [".supabase.co", ".supabase.in", ".supabase.red"]

  /// Reports whether `host` is a Supabase project host that has not already been pointed at
  /// storage.
  private static func isLegacySupabaseHost(_ host: String) -> Bool {
    !host.contains("storage.supabase.")
      && legacySupabaseHostSuffixes.contains(where: host.hasSuffix)
  }

  /// The configuration used to initialize this client instance.
  let configuration: StorageClientConfiguration

  private let http: any HTTPClientType

  /// Creates a ``StorageApi`` with the given configuration.
  ///
  /// - Parameter configuration: The configuration that controls the endpoint URL, authentication
  ///   headers, JSON codecs, and HTTP session.
  init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }

    // if legacy uri is used, replace with new storage host (disables request buffering to allow > 50GB uploads)
    // "project-ref.supabase.co" becomes "project-ref.storage.supabase.co"
    if configuration.useNewHostname == true {
      // `configuration.url` is supplied once, at construction, so a URL that cannot be decomposed
      // into host components is a programmer error, not a runtime condition. Trap here, where the
      // offending value is, rather than letting it fail later as an opaque `URLError`.
      guard
        var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false),
        let host = components.host
      else {
        preconditionFailure("Storage client initialized with an invalid URL: \(configuration.url)")
      }

      if Self.isLegacySupabaseHost(host) {
        // Substitute on the same label boundary the check used, so a host that happens to start
        // with `supabase.` is not rewritten at that leading position too.
        components.host = host.replacingOccurrences(of: ".supabase.", with: ".storage.supabase.")

        guard let rewritten = components.url else {
          preconditionFailure("Rewriting the storage host produced an invalid URL: \(components)")
        }

        configuration.url = rewritten
      }
    }

    self.configuration = configuration

    let middlewares: [any ClientMiddleware] = [
      LoggerInterceptor(logger: configuration.logger)
    ]

    http = HTTPClient(
      transport: FetchTransport(fetch: configuration.session.fetch),
      middlewares: middlewares
    )
  }

  /// Returns a new ``StorageApi`` with an additional HTTP header merged into
  /// ``configuration``'s headers, included in all requests made by the returned instance.
  ///
  /// Because ``StorageApi`` is an immutable value type, this method does not mutate `self` — it
  /// returns a new instance. Discarding the return value is a no-op, so always use the result:
  ///
  /// ```swift
  /// storage.from("avatars")
  ///   .setHeader("x-custom-header", forKey: "X-Custom-Header")
  ///   .list()
  /// ```
  ///
  /// - Parameters:
  ///   - value: The value of the header field.
  ///   - key: The name of the header field. The key is case-insensitively stored as lowercase.
  /// - Returns: A new ``StorageApi`` with the header merged into ``configuration``'s headers.
  func setHeader(_ value: String, forKey key: String) -> Self {
    var configuration = configuration
    configuration.headers[key.lowercased()] = value
    return StorageApi(configuration: configuration)
  }

  @discardableResult
  func execute(_ request: Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse {
    var request = request
    request.headers = HTTPFields(configuration.headers).merging(with: request.headers)

    let response = try await http.send(request)

    guard (200..<300).contains(response.statusCode) else {
      if let error = try? configuration.decoder.decode(
        StorageError.self,
        from: response.data
      ) {
        throw error
      }

      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }

    return response
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
