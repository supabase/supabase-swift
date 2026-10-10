import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Internal implementation detail shared by ``StorageClient``, ``StorageBucket``, and the
/// Vectors trio (``StorageVectorsClient``, ``VectorBucketClient``, ``VectorIndexClient``).
///
/// Holds the ``StorageClientConfiguration``, the ``StorageRequests`` builder for its base URL,
/// and sends requests through the shared `HTTPClient`. Each of the types above holds a
/// ``StorageAPI`` value and delegates to it rather than inheriting from it.
struct StorageAPI: Sendable {
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
  private(set) var configuration: StorageClientConfiguration

  /// Builds the request for each route under ``configuration``'s URL.
  let requests: StorageRequests

  /// Creates a ``StorageAPI`` with the given configuration.
  ///
  /// - Parameter configuration: The configuration that controls the endpoint URL, authentication
  ///   headers, and transport.
  init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if HTTPFields(configuration.headers)[.xClientInfo] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }

    // if legacy uri is used, replace with new storage host (disables request buffering to allow > 50GB uploads)
    // "project-ref.supabase.co" becomes "project-ref.storage.supabase.co"
    if configuration.usesNewHostname == true {
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
    self.requests = StorageRequests(url: configuration.url)
  }

  /// Returns a copy with `value` merged into ``configuration``'s headers, included in all requests
  /// made by the returned instance.
  ///
  /// - Parameters:
  ///   - value: The value of the header field.
  ///   - key: The name of the header field. The key is case-insensitively stored as lowercase.
  func setHeader(_ value: String, forKey key: String) -> Self {
    var copy = self
    copy.configuration.headers[key.lowercased()] = value
    return copy
  }

  /// Sends `head` with the client's default headers and returns the response body.
  @discardableResult
  func execute(_ head: HTTPRequest, body: Data? = nil) async throws -> Data {
    try await execute(StorageRequest(head: head, body: body.map { HTTPBody($0) }))
  }

  /// Sends `request` with the client's default headers and returns the response body.
  ///
  /// Only `GET`, `HEAD` and ``StorageRequest/replayable`` requests are retried, and only when
  /// ``StorageClientConfiguration/retryEnabled`` is `true`.
  @discardableResult
  func execute(_ request: StorageRequest) async throws -> Data {
    var policy = configuration.retryEnabled ? RetryPolicy.default : .disabled
    if request.replayable { policy.retryableMethods.insert(request.head.method) }
    let retry = RetryRequestInterceptor(policy: policy, clock: configuration.clock)
    let http = HTTPClient(
      configuration: configuration.http,
      retrying: retry,
      appending: [LoggerInterceptor(logger: configuration.logger)])

    var head = request.head
    head.headerFields = HTTPFields(configuration.headers).merging(with: head.headerFields)

    let response: HTTPResponse
    let data: Data
    do {
      let (responseHead, responseBody) = try await http.stream(head, body: request.body)
      response = responseHead
      if let responseBody {
        data = try await Data(collecting: responseBody, upTo: .max)
      } else {
        data = Data()
      }
    } catch {
      // Only the network layer's own failures are relabelled. `CancellationError`, and anything
      // thrown by user code that runs inside `stream` (a custom `ClientTransport` or middleware, an `accessToken` closure),
      // propagate as themselves.
      guard let urlError = error as? URLError else { throw error }
      // `URLSession` reports a cancelled `Task` as `URLError(.cancelled)`. A `.cancelled` with no
      // task cancellation behind it (a middleware cancelled the request) stays a transport error.
      if urlError.code == .cancelled, Task.isCancelled { throw CancellationError() }
      throw StorageError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    guard (200..<300).contains(response.status.code) else {
      if let serverError = try? JSONDecoder.storage.decode(
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
        kind: .server,
        message: "Unexpected response with status code \(response.status.code).",
        response: HTTPErrorResponse(response, body: data)
      )
    }

    return data
  }
}

extension Data {
  /// Shadows `Data.decoded(as:decoder:)` from Helpers inside the Storage module so every
  /// existing decode call site throws ``StorageError`` with kind `.decoding` instead of a bare
  /// `DecodingError`. Same-module declarations win over imported ones with the same signature.
  func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder = .storage) throws -> T {
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
