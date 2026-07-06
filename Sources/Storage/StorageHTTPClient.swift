import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// An HTTP session abstraction used by the Storage client to perform network requests.
///
/// ``StorageHTTPSession`` wraps a `URLSession` (or any custom async fetch/upload closures) so that
/// the Storage client can be tested without a real network connection and can be configured to use
/// a custom session (e.g. with background upload support).
///
/// The default initializer uses `URLSession.shared`.
///
/// ```swift
/// // Use a custom URLSession with a specific configuration
/// let config = URLSessionConfiguration.default
/// config.timeoutIntervalForRequest = 60
/// let session = URLSession(configuration: config)
/// let httpSession = StorageHTTPSession(session: session)
///
/// let storage = SupabaseStorageClient(
///   configuration: StorageClientConfiguration(
///     url: storageURL,
///     headers: ["Authorization": "Bearer \(token)"],
///     session: httpSession
///   )
/// )
/// ```
public struct StorageHTTPSession: Sendable {
  /// A closure that performs a data fetch for a given `URLRequest`.
  ///
  /// Returns the raw response body and the `URLResponse`.
  public var fetch: @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)

  /// A closure that performs a data upload for a given `URLRequest` and body `Data`.
  ///
  /// Returns the raw response body and the `URLResponse`.
  public var upload:
    @Sendable (_ request: URLRequest, _ data: Data) async throws -> (Data, URLResponse)

  /// Creates a ``StorageHTTPSession`` with custom fetch and upload closures.
  ///
  /// - Parameters:
  ///   - fetch: A closure that executes a network fetch request and returns the response data and metadata.
  ///   - upload: A closure that uploads data for a request and returns the response data and metadata.
  public init(
    fetch: @escaping @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse),
    upload:
      @escaping @Sendable (_ request: URLRequest, _ data: Data) async throws -> (
        Data, URLResponse
      )
  ) {
    self.fetch = fetch
    self.upload = upload
  }

  /// Creates a ``StorageHTTPSession`` backed by a `URLSession`.
  ///
  /// - Parameter session: The `URLSession` to use for network requests. Defaults to `URLSession.shared`.
  public init(session: URLSession = .shared) {
    self.init(
      fetch: { try await session.data(for: $0) },
      upload: { try await session.upload(for: $0, from: $1) }
    )
  }
}
