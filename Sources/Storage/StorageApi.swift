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

  private let http: HTTPClient

  /// Creates a ``StorageApi`` with the given configuration.
  ///
  /// - Parameter configuration: The configuration that controls the endpoint URL, authentication
  ///   headers, JSON codecs, and transport.
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

    let interceptors: [any ClientMiddleware] = [
      LoggerInterceptor(logger: configuration.logger)
    ]

    http = HTTPClient(configuration: configuration.http, appending: interceptors)
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

  /// Sends `request` with the client's default headers and returns the response body.
  @discardableResult
  func execute(_ request: HTTPRequest, body: Data? = nil) async throws -> Data {
    var request = request
    request.headerFields = HTTPFields(configuration.headers).merging(with: request.headerFields)

    let response: HTTPResponse
    let data: Data
    do {
      (response, data) = try await http.send(request, body: body)
    } catch {
      // Only the network layer's own failures are relabelled. `CancellationError`, and anything
      // thrown by user code that runs inside `send` (a custom `fetch`, an `accessToken` closure),
      // propagate as themselves.
      guard let urlError = error as? URLError else { throw error }
      throw StorageError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    guard (200..<300).contains(response.status.code) else {
      if let serverError = try? configuration.decoder.decode(
        StorageError.ServerError.self, from: data)
      {
        throw StorageError(
          kind: .server,
          message: serverError.message,
          serverError: serverError,
          response: HTTPErrorResponse(response, body: data)
        )
      }

      throw StorageError(
        kind: .unexpectedResponse,
        message: "Unexpected response with status code \(response.status.code).",
        response: HTTPErrorResponse(response, body: data)
      )
    }

    return data
  }

  /// Sends `formData` as a multipart upload, defaulting `Content-Type` and `Cache-Control`.
  func upload(
    _ request: HTTPRequest,
    formData: MultipartFormData,
    options: FileOptions
  ) async throws -> Data {
    var request = request
    if request.headerFields[.contentType] == nil {
      request.headerFields[.contentType] = formData.contentType
    }
    if request.headerFields[.cacheControl] == nil {
      request.headerFields[.cacheControl] = "max-age=\(options.cacheControl)"
    }
    return try await execute(request, body: try formData.encode())
  }
}

extension Data {
  /// Shadows `Data.decoded(as:decoder:)` from Helpers inside the Storage module so every
  /// existing decode call site throws ``StorageError`` with kind `.decoding` instead of a bare
  /// `DecodingError`. Same-module declarations win over imported ones with the same signature.
  func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws
    -> T
  {
    do {
      return try decoder.decode(T.self, from: self)
    } catch {
      throw StorageError(
        kind: .decoding,
        message: "Failed to decode the Storage response as \(T.self).",
        underlyingError: error
      )
    }
  }
}
