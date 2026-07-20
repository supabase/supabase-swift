import ConcurrencyExtras
import Foundation
import HTTPRuntime
import HTTPTypes

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

  private struct MutableState {
    var headers: [String: String]
  }

  private let mutableState: LockIsolated<MutableState>
  private let http: any HTTPClientType

  let generatedClient: StorageGeneratedClient

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

    let mutableState = self.mutableState
    generatedClient = StorageGeneratedClient(
      baseURL: configuration.url,
      transport: HeaderInjectingTransport(
        inner: URLSessionTransport(
          data: { [session = configuration.session] request, _ in
            try await session.fetch(request)
          },
          uploadFromBodyData: { [session = configuration.session] request, data, _ in
            try await session.upload(request, data)
          },
          uploadFromFile: { [session = configuration.session] request, fileURL, delegate in
            try await session.uploadFromFile(request, fileURL, delegate)
          },
          bytes: { [session = configuration.session] request, delegate in
            try await session.bytes(request, delegate)
          }
        ),
        headers: { mutableState.headers }
      )
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

  @discardableResult
  func execute(_ request: Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse {
    var request = request
    let headers = mutableState.headers
    request.headers = HTTPFields(headers).merging(with: request.headers)

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

  /// Wraps an async operation that may throw an ``ErrorSchema`` or ``HTTPRuntime.HTTPError`` and converts
  /// it into a ``StorageError`` if applicable. This is used to maintain backward compatibility with the previous error handling behavior of the Storage API.
  func withBackwardCompatibleErrorHandling<T>(_ operation: () async throws -> T) async throws -> T {
    // TODO: check for other error types that may need to be converted for backward compatibility.
    do {
      return try await operation()
    } catch let error as ErrorSchema {
      throw StorageError(
        statusCode: error.statusCode,
        message: error.message,
        error: error.error
      )
    } catch let error as HTTPRuntime.HTTPError {
      if case .unexpectedStatus(let status, let body) = error {
        if let error = try? configuration.decoder.decode(StorageError.self, from: body) {
          throw error
        }

        throw StorageError(
          statusCode: "\(status)",
          message: String(data: body, encoding: .utf8) ?? "Unknown error"
        )
      } else {
        throw error
      }
    } catch {
      throw error
    }
  }
}

/// Wraps an `HTTPTransport`, merging this client's dynamic per-instance
/// headers (`apikey`/`Authorization`/custom `setHeader` values) into every
/// outgoing request before delegating. The generated client builds requests
/// with empty headers by default — this gives calls that go through
/// `generatedClient` the same auth/header behavior as the hand-written
/// `execute(_:)` path, which merges `mutableState.headers` explicitly.
private struct HeaderInjectingTransport: HTTPTransport {
  let inner: any HTTPTransport
  let headers: @Sendable () -> [String: String]

  func send(_ request: HTTPRuntime.HTTPRequest, uploadProgress: ProgressHandler?) async throws
    -> HTTPRuntime.HTTPResponse
  {
    try await inner.send(injectingHeaders(into: request), uploadProgress: uploadProgress)
  }

  func stream(_ request: HTTPRuntime.HTTPRequest) async throws -> HTTPResponseStream {
    try await inner.stream(injectingHeaders(into: request))
  }

  private func injectingHeaders(into request: HTTPRuntime.HTTPRequest) -> HTTPRuntime.HTTPRequest {
    var request = request
    for (key, value) in headers() where request.headers[key] == nil {
      request.headers[key] = value
    }
    return request
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
