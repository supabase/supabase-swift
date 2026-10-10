public import Foundation
public import Helpers
public import Logging

/// Configuration for the Supabase Storage client.
///
/// Pass a ``StorageClientConfiguration`` to ``StorageClient`` to control the Storage
/// endpoint URL, authentication headers, and the underlying transport.
///
/// ```swift
/// let configuration = StorageClientConfiguration(
///   url: URL(string: "https://project.supabase.co/storage/v1")!,
///   headers: ["Authorization": "Bearer \(accessToken)"]
/// )
/// let storage = StorageClient(configuration: configuration)
/// ```
///
/// ## Topics
///
/// ### Creating a configuration
///
/// - ``init(url:headers:http:logger:usesNewHostname:retryEnabled:accessToken:)``
///
/// ### Configuration properties
///
/// - ``url``
/// - ``headers``
/// - ``http``
/// - ``logger``
/// - ``usesNewHostname``
/// - ``retryEnabled``
/// - ``accessToken``
public struct StorageClientConfiguration: Sendable {
  /// The base URL of the Storage API endpoint (e.g. `https://project.supabase.co/storage/v1`).
  public var url: URL

  /// HTTP headers sent with every request.
  ///
  /// A static `Authorization` here wins over ``accessToken``: the token is only sent when the
  /// request carries no `Authorization`. Prefer ``accessToken`` for a token that rotates.
  public var headers: [String: String]

  /// The transport and middleware chain every request goes through.
  public let http: HTTPClientConfiguration

  /// The logger used for debugging HTTP interactions. Defaults to a build-config-aware logger.
  public let logger: Logging.Logger

  /// When `true`, rewrites `project.supabase.co` hostnames to `project.storage.supabase.co`,
  /// which disables request buffering and enables uploads larger than 50 GB.
  public let usesNewHostname: Bool

  /// Whether transient failures of reads are retried. Defaults to `true`.
  ///
  /// Only reads are replayed: `GET` and `HEAD` requests and ``StorageBucket/list(path:options:)``,
  /// up to three attempts with jittered backoff. Uploads, moves, copies, removals and bucket
  /// changes are never replayed.
  public let retryEnabled: Bool

  /// Resolved for every request and sent as `Authorization: Bearer <token>` unless the request
  /// already carries `Authorization`. `nil` (the default) sends no bearer token.
  ///
  /// For a standalone client whose session token rotates; `SupabaseClient` injects its own
  /// token middleware and leaves this `nil`.
  public var accessToken: (@Sendable () async throws -> String?)?

  /// The clock the waits between retries sleep on.
  package var clock: any Clock<Duration> = ContinuousClock()

  /// Creates a ``StorageClientConfiguration``.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Storage API endpoint.
  ///   - headers: HTTP headers sent with every request.
  ///   - http: The transport and middleware chain every request goes through.
  ///   - logger: The logger to use. Defaults to a build-config-aware logger; pass a logger backed by
  ///     `SwiftLogNoOpLogHandler` to disable logging entirely.
  ///   - usesNewHostname: When `true`, the storage-specific hostname is used, enabling uploads over 50 GB.
  ///   - retryEnabled: Whether transient failures of reads are retried.
  ///   - accessToken: Resolved for every request and sent as a bearer token when the request
  ///     carries no `Authorization` header.
  public init(
    url: URL,
    headers: [String: String],
    http: HTTPClientConfiguration = .init(),
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.storage"),
    usesNewHostname: Bool = false,
    retryEnabled: Bool = true,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) {
    self.url = url
    self.headers = headers
    self.http = http
    var logger = logger
    logger[metadataKey: "system"] = "storage"
    self.logger = logger
    self.usesNewHostname = usesNewHostname
    self.retryEnabled = retryEnabled
    self.accessToken = accessToken
  }
}

/// The top-level Supabase Storage client for managing buckets and files.
///
/// ``StorageClient`` provides bucket-management operations directly and a ``from(_:)``
/// method to obtain a ``StorageBucket`` scoped to a specific bucket.
///
/// Typically you obtain an instance via the main `SupabaseClient`:
///
/// ```swift
/// let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
/// let storage = client.storage
///
/// // Upload a file
/// try await storage.from("avatars").upload(path: "user123.png", data: imageData)
///
/// // List all buckets
/// let buckets = try await storage.listBuckets()
/// ```
///
/// ## Topics
///
/// ### Creating a client
///
/// - ``init(configuration:)``
///
/// ### Configuration
///
/// - ``configuration``
///
/// ### Customizing headers
///
/// - ``setHeader(_:forKey:)``
///
/// ### Accessing buckets
///
/// - ``from(_:)``
///
/// ### Bucket management
///
/// - ``listBuckets()``
/// - ``bucket(_:)``
/// - ``createBucket(_:options:)``
/// - ``updateBucket(_:options:)``
/// - ``emptyBucket(_:)``
/// - ``deleteBucket(_:)``
/// - ``purgeCache(bucket:transformationsOnly:)``
public struct StorageClient: Sendable {
  let api: StorageAPI

  /// The configuration used to initialize this client instance.
  public var configuration: StorageClientConfiguration { api.configuration }

  /// Creates a ``StorageClient`` with the given configuration.
  ///
  /// - Parameter configuration: The configuration that controls the endpoint URL, authentication
  ///   headers, JSON codecs, and transport.
  public init(configuration: StorageClientConfiguration) {
    api = StorageAPI(configuration: configuration)
  }

  init(api: StorageAPI) {
    self.api = api
  }

  /// Returns a new ``StorageClient`` with an additional HTTP header merged into the
  /// underlying configuration, included in all requests made by the returned instance (and by
  /// ``StorageBucket`` instances subsequently obtained via ``from(_:)``).
  ///
  /// Because ``StorageClient`` is an immutable value type, this method does not mutate
  /// `self` — it returns a new instance. Discarding the return value is a no-op, so always use
  /// the result:
  ///
  /// ```swift
  /// let storage = client.storage.setHeader("x-custom-header", forKey: "X-Custom-Header")
  /// ```
  ///
  /// - Parameters:
  ///   - value: The value of the header field.
  ///   - key: The name of the header field. The key is case-insensitively stored as lowercase.
  /// - Returns: A new ``StorageClient`` with the header merged into the configuration's
  ///   headers.
  public func setHeader(_ value: String, forKey key: String) -> Self {
    StorageClient(api: api.setHeader(value, forKey: key))
  }

  /// Returns a ``StorageBucket`` scoped to the given bucket.
  ///
  /// Use the returned object to upload, download, list, move, copy, or delete files within the
  /// specified bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to operate on.
  /// - Returns: A ``StorageBucket`` configured for the given bucket.
  public func from(_ id: String) -> StorageBucket {
    StorageBucket(id: id, api: api)
  }

  /// A client for managing vector buckets.
  ///
  /// ```swift
  /// try await client.storage.vectors.createBucket("documents")
  /// let buckets = try await client.storage.vectors.listBuckets().vectorBuckets
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  @_spi(Experimental)
  public var vectors: StorageVectorsClient {
    StorageVectorsClient(api: api)
  }
}
