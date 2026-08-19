public import Foundation
public import Logging

/// Configuration for the Supabase Storage client.
///
/// Pass a ``StorageClientConfiguration`` to ``SupabaseStorageClient`` to control the Storage
/// endpoint URL, authentication headers, JSON coding strategies, and the underlying HTTP session.
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
/// - ``init(url:headers:encoder:decoder:session:logger:useNewHostname:)``
///
/// ### Configuration properties
///
/// - ``url``
/// - ``headers``
/// - ``encoder``
/// - ``decoder``
/// - ``session``
/// - ``logger``
/// - ``useNewHostname``
public struct StorageClientConfiguration: Sendable {
  /// The base URL of the Storage API endpoint (e.g. `https://project.supabase.co/storage/v1`).
  public var url: URL

  /// HTTP headers sent with every request, such as the `Authorization` header.
  public var headers: [String: String]

  /// The JSON encoder used to serialize request bodies.
  public let encoder: JSONEncoder

  /// The JSON decoder used to deserialize response bodies.
  public let decoder: JSONDecoder

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
  ///   - encoder: The JSON encoder for request bodies. Defaults to a `snake_case`-converting encoder.
  ///   - decoder: The JSON decoder for response bodies. Defaults to a decoder configured for the
  ///     Supabase API's date format.
  ///   - session: The HTTP session used for networking. Defaults to a session backed by `URLSession.shared`.
  ///   - logger: The logger to use. Defaults to a build-config-aware logger; pass a logger backed by
  ///     `SwiftLogNoOpLogHandler` to disable logging entirely.
  ///   - useNewHostname: When `true`, the storage-specific hostname is used, enabling uploads over 50 GB.
  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder? = nil,
    decoder: JSONDecoder? = nil,
    session: StorageHTTPSession = .init(),
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.storage"),
    useNewHostname: Bool = false
  ) {
    self.url = url
    self.headers = headers
    self.encoder = encoder ?? .storageEncoder
    self.decoder = decoder ?? .supabase()
    self.session = session
    var logger = logger
    logger[metadataKey: "system"] = "storage"
    self.logger = logger
    self.useNewHostname = useNewHostname
  }
}

/// The top-level Supabase Storage client for managing buckets and files.
///
/// ``SupabaseStorageClient`` inherits all bucket-management operations from ``StorageBucketApi``
/// and provides a ``from(_:)`` method to obtain a ``StorageFileApi`` scoped to a specific bucket.
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
/// ### Accessing buckets
///
/// - ``from(_:)``
///
/// ### Bucket management
///
/// - ``StorageBucketApi/listBuckets()``
/// - ``StorageBucketApi/getBucket(_:)``
/// - ``StorageBucketApi/createBucket(_:options:)``
/// - ``StorageBucketApi/updateBucket(_:options:)``
/// - ``StorageBucketApi/emptyBucket(_:)``
/// - ``StorageBucketApi/deleteBucket(_:)``
public class SupabaseStorageClient: StorageBucketApi, @unchecked Sendable {
  /// Returns a ``StorageFileApi`` scoped to the given bucket.
  ///
  /// Use the returned object to upload, download, list, move, copy, or delete files within the
  /// specified bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to operate on.
  /// - Returns: A ``StorageFileApi`` configured for the given bucket.
  public func from(_ id: String) -> StorageFileApi {
    StorageFileApi(bucketId: id, configuration: configuration)
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
    StorageVectorsClient(api: self)
  }
}
