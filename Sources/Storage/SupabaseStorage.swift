import Foundation

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

  /// An optional logger for debugging HTTP interactions.
  public let logger: (any SupabaseLogger)?

  /// When `true`, rewrites `project.supabase.co` hostnames to `project.storage.supabase.co`,
  /// which disables request buffering and enables uploads larger than 50 GB.
  public let useNewHostname: Bool

  /// Creates a ``StorageClientConfiguration``.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Storage API endpoint.
  ///   - headers: HTTP headers sent with every request.
  ///   - encoder: The JSON encoder for request bodies. Defaults to ``JSONEncoder/defaultStorageEncoder``.
  ///   - decoder: The JSON decoder for response bodies. Defaults to ``JSONDecoder/defaultStorageDecoder``.
  ///   - session: The HTTP session used for networking. Defaults to a session backed by `URLSession.shared`.
  ///   - logger: An optional logger. Pass `nil` to disable logging.
  ///   - useNewHostname: When `true`, the storage-specific hostname is used, enabling uploads over 50 GB.
  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder = .defaultStorageEncoder,
    decoder: JSONDecoder = .defaultStorageDecoder,
    session: StorageHTTPSession = .init(),
    logger: (any SupabaseLogger)? = nil,
    useNewHostname: Bool = false
  ) {
    self.url = url
    self.headers = headers
    self.encoder = encoder
    self.decoder = decoder
    self.session = session
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
}
