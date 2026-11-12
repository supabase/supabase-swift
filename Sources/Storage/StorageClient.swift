public import Foundation
public import HTTPTypes
public import Helpers
public import Logging

extension StorageClient {
  /// Configuration for the Supabase Storage client.
  ///
  /// Pass a ``StorageClient/Configuration`` to ``StorageClient/init(configuration:)`` to control
  /// the Storage endpoint URL, authentication headers, and the underlying transport.
  ///
  /// ```swift
  /// let configuration = StorageClient.Configuration(
  ///   url: URL(string: "https://project.supabase.co/storage/v1")!,
  ///   headers: [.apikey: key],
  ///   http: HTTPClientConfiguration(
  ///     middlewares: [AccessTokenMiddleware { try await session.accessToken }]
  ///   )
  /// )
  /// let storage = try StorageClient(configuration: configuration)
  /// ```
  ///
  /// A user's token enters a request through the middleware chain in ``http``, never through a
  /// configuration field: `AccessTokenMiddleware` resolves it for every request, so a token that
  /// rotates is always current, and `SupabaseClient` installs the same middleware for its own
  /// Storage client. A static `Authorization` in ``headers`` is sent as-is and wins over any
  /// middleware, which only sets the header when the request has none.
  ///
  /// ## Topics
  ///
  /// ### Creating a configuration
  ///
  /// - ``init(url:headers:usesNewHostname:http:logger:retryEnabled:clock:)``
  ///
  /// ### Configuration properties
  ///
  /// - ``url``
  /// - ``headers``
  /// - ``usesNewHostname``
  /// - ``http``
  /// - ``logger``
  /// - ``retryEnabled``
  /// - ``clock``
  public struct Configuration: Sendable {
    /// The base URL of the Storage API endpoint (e.g. `https://project.supabase.co/storage/v1`).
    public var url: URL

    /// HTTP headers sent with every request. `HTTPFields` matches names case-insensitively.
    ///
    /// A static `Authorization` here wins over any middleware in ``http``. For a token that
    /// rotates, leave it out and add an `AccessTokenMiddleware` instead.
    public var headers: HTTPFields

    /// When `true`, rewrites `project.supabase.co` hostnames to `project.storage.supabase.co`,
    /// which disables request buffering and enables uploads larger than 50 GB.
    public var usesNewHostname: Bool

    /// How resumable uploads are chunked, retried and persisted.
    ///
    /// - Warning: Experimental. See ``ResumableUpload``.
    @_spi(Experimental) public var resumable = ResumableUploadConfiguration()

    /// The transport and middleware chain every request goes through.
    ///
    /// To send a user's access token, add an `AccessTokenMiddleware` to its middlewares. It runs
    /// on every attempt, so a retried request gets a fresh token. A provider failure throws
    /// ``StorageError`` with kind ``StorageError/Kind-swift.struct/accessToken``. An
    /// `Authorization` header in ``headers`` wins over the middleware.
    public var http: HTTPClientConfiguration

    /// The logger used for debugging HTTP interactions. Defaults to a build-config-aware logger.
    ///
    /// The client removes tokens, secrets, and URL query strings from each line before your handler
    /// sees it, and tags the logger with the `system` metadata key set to `storage`.
    public var logger: Logging.Logger

    /// Whether transient failures of reads are retried. Defaults to `true`.
    ///
    /// Only reads are replayed: `GET` and `HEAD` requests, ``StorageBucket/list(path:options:)``
    /// and each page of ``StorageBucket/objects(prefix:options:)``, up to three attempts with
    /// jittered backoff. Uploads, moves, copies, removals and bucket changes are never replayed.
    public var retryEnabled: Bool

    /// The clock the waits between retries sleep on.
    ///
    /// Defaults to `ContinuousClock()`. Pass a `TestClock` to drive retries deterministically in
    /// tests instead of waiting out real seconds. `TestClock` comes from
    /// [swift-clocks](https://github.com/pointfreeco/swift-clocks); add it to your test target
    /// yourself, as this package does not export it.
    public var clock: any Clock<Duration>

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - url: The base URL of the Storage API endpoint.
    ///   - headers: HTTP headers sent with every request.
    ///   - usesNewHostname: When `true`, the storage-specific hostname is used, enabling uploads
    ///     over 50 GB.
    ///   - http: The transport and middleware chain every request goes through.
    ///   - logger: The logger to use. Defaults to a build-config-aware logger; pass a logger backed
    ///     by `SwiftLogNoOpLogHandler` to disable logging entirely.
    ///   - retryEnabled: Whether transient failures of reads are retried.
    ///   - clock: The clock the waits between retries sleep on. Defaults to `ContinuousClock()`.
    public init(
      url: URL,
      headers: HTTPFields = [:],
      usesNewHostname: Bool = false,
      http: HTTPClientConfiguration = .init(),
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.storage"),
      retryEnabled: Bool = true,
      clock: any Clock<Duration> = ContinuousClock()
    ) {
      self.url = url
      self.headers = headers
      self.usesNewHostname = usesNewHostname
      self.http = http
      self.logger = logger
      self.retryEnabled = retryEnabled
      self.clock = clock
    }
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
/// let client = try SupabaseClient(supabaseURL: url, supabaseKey: key)
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
/// - ``settingHeader(name:value:)``
///
/// ### Accessing buckets
///
/// - ``from(_:)``
///
/// ### Bucket management
///
/// - ``listBuckets(options:)``
/// - ``bucket(_:)``
/// - ``createBucket(_:options:)``
/// - ``updateBucket(_:options:)``
/// - ``emptyBucket(_:)``
/// - ``deleteBucket(_:)``
/// - ``purgeCache(bucket:transformationsOnly:)``
///
/// ### Bucket lifecycle
///
/// - ``lifecycle(forBucket:)``
/// - ``setLifecycle(_:forBucket:)``
/// - ``deleteLifecycle(forBucket:)``
public struct StorageClient: Sendable {
  let api: StorageAPI

  /// The configuration used to initialize this client instance.
  public var configuration: Configuration { api.configuration }

  /// Creates a ``StorageClient`` with the given configuration.
  ///
  /// - Parameter configuration: The configuration that controls the endpoint URL, authentication
  ///   headers, and transport.
  /// - Throws: ``StorageError`` with kind ``StorageError/Kind-swift.struct/invalidConfiguration``
  ///   if `configuration.url` has no scheme, no host, or cannot be split into components.
  public init(configuration: Configuration) throws {
    api = try StorageAPI(configuration: configuration)
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
  /// let storage = client.storage.settingHeader(
  ///   name: .init("X-Custom-Header")!, value: "x-custom-header")
  /// ```
  ///
  /// - Parameters:
  ///   - name: The header field. Names match case-insensitively.
  ///   - value: The value of the header field.
  /// - Returns: A new ``StorageClient`` with the header merged into the configuration's
  ///   headers.
  public func settingHeader(name: HTTPField.Name, value: String) -> Self {
    StorageClient(api: api.settingHeader(name: name, value: value))
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
  /// let buckets = try await client.storage.vectors.listBuckets().page().vectorBuckets
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageVectorsClient``.
  @_spi(Experimental)
  public var vectors: StorageVectorsClient {
    StorageVectorsClient(api: api)
  }

  /// A client for managing analytics (Iceberg) buckets.
  ///
  /// ```swift
  /// try await client.storage.analytics.createBucket("events")
  /// ```
  ///
  /// - Warning: Experimental. See ``StorageAnalyticsClient``.
  @_spi(Experimental)
  public var analytics: StorageAnalyticsClient {
    StorageAnalyticsClient(api: api)
  }
}
