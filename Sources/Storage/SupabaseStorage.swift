public import Foundation
public import Logging

/// Configuration for the Supabase Storage client.
///
/// Pass a ``StorageClientConfiguration`` to ``SupabaseStorageClient`` to control the Storage
/// endpoint URL, authentication headers, and the underlying HTTP session.
///
/// ```swift
/// let configuration = StorageClientConfiguration(
///   url: URL(string: "https://project.supabase.co/storage/v1")!,
///   headers: ["Authorization": "Bearer \(accessToken)"]
/// )
/// let storage = SupabaseStorageClient(configuration: configuration)
/// ```
///
/// ## Topics
///
/// ### Creating a configuration
///
/// - ``init(url:headers:session:logger:useNewHostname:)``
///
/// ### Configuration properties
///
/// - ``url``
/// - ``headers``
/// - ``session``
/// - ``logger``
/// - ``useNewHostname``
public struct StorageClientConfiguration: Sendable {
  /// The base URL of the Storage API endpoint (e.g. `https://project.supabase.co/storage/v1`).
  public var url: URL

  /// HTTP headers sent with every request, such as the `Authorization` header.
  public var headers: [String: String]

  /// The JSON encoder used to serialize request bodies. Not publicly configurable: Storage only
  /// ever encodes server-defined shapes, so there's no case for letting callers customize it.
  let encoder: JSONEncoder = .storageEncoder

  /// The JSON decoder used to deserialize response bodies. Not publicly configurable: Storage only
  /// ever decodes server-defined shapes, so there's no case for letting callers customize it.
  let decoder: JSONDecoder = .supabase()

  /// The HTTP session abstraction used to execute requests.
  public let session: StorageHTTPSession

  /// The logger used for debugging HTTP interactions. Defaults to a build-config-aware logger.
  public let logger: Logging.Logger

  /// When `true`, rewrites `project.supabase.co` hostnames to `project.storage.supabase.co`,
  /// which disables request buffering and enables uploads larger than 50 GB.
  public let useNewHostname: Bool

  /// Creates a ``StorageClientConfiguration``.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Storage API endpoint.
  ///   - headers: HTTP headers sent with every request.
  ///   - session: The HTTP session used for networking. Defaults to a session backed by `URLSession.shared`.
  ///   - logger: The logger to use. Defaults to a build-config-aware logger; pass a logger backed by
  ///     `SwiftLogNoOpLogHandler` to disable logging entirely.
  ///   - useNewHostname: When `true`, the storage-specific hostname is used, enabling uploads over 50 GB.
  public init(
    url: URL,
    headers: [String: String],
    session: StorageHTTPSession = .init(),
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.storage"),
    useNewHostname: Bool = false
  ) {
    self.url = url
    self.headers = headers
    self.session = session
    var logger = logger
    logger[metadataKey: "system"] = "storage"
    self.logger = logger
    self.useNewHostname = useNewHostname
  }
}

/// The top-level Supabase Storage client for managing buckets and files.
///
/// ``SupabaseStorageClient`` provides bucket-management operations directly and a ``from(_:)``
/// method to obtain a ``StorageFileApi`` scoped to a specific bucket.
///
/// Typically you obtain an instance via the main `SupabaseClient`:
///
/// ```swift
/// let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
/// let storage = client.storage
///
/// // Upload a file
/// try await storage.from("avatars").upload("user123.png", data: imageData)
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
/// - ``getBucket(_:)``
/// - ``createBucket(_:options:)``
/// - ``updateBucket(_:options:)``
/// - ``emptyBucket(_:)``
/// - ``deleteBucket(_:)``
public struct SupabaseStorageClient: Sendable {
  let api: StorageApi

  /// The configuration used to initialize this client instance.
  public var configuration: StorageClientConfiguration { api.configuration }

  /// Creates a ``SupabaseStorageClient`` with the given configuration.
  ///
  /// - Parameter configuration: The configuration that controls the endpoint URL, authentication
  ///   headers, JSON codecs, and HTTP session.
  public init(configuration: StorageClientConfiguration) {
    api = StorageApi(configuration: configuration)
  }

  init(api: StorageApi) {
    self.api = api
  }

  /// Returns a new ``SupabaseStorageClient`` with an additional HTTP header merged into the
  /// underlying configuration, included in all requests made by the returned instance (and by
  /// ``StorageFileApi`` instances subsequently obtained via ``from(_:)``).
  ///
  /// Because ``SupabaseStorageClient`` is an immutable value type, this method does not mutate
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
  /// - Returns: A new ``SupabaseStorageClient`` with the header merged into the configuration's
  ///   headers.
  public func setHeader(_ value: String, forKey key: String) -> Self {
    SupabaseStorageClient(api: api.setHeader(value, forKey: key))
  }

  /// Returns a ``StorageFileApi`` scoped to the given bucket.
  ///
  /// Use the returned object to upload, download, list, move, copy, or delete files within the
  /// specified bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to operate on.
  /// - Returns: A ``StorageFileApi`` configured for the given bucket.
  public func from(_ id: String) -> StorageFileApi {
    StorageFileApi(bucketId: id, api: api)
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
