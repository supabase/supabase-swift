public import Foundation
public import HTTPTypes

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
/// - ``usesNewHostname``
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
  public var usesNewHostname: Bool

  /// When `true`, rewrites `project.supabase.co` hostnames to `project.storage.supabase.co`,
  /// which disables request buffering and enables uploads larger than 50 GB.
  @available(*, deprecated, renamed: "usesNewHostname")
  public var useNewHostname: Bool { usesNewHostname }

  /// Creates a ``StorageClientConfiguration``.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Storage API endpoint.
  ///   - headers: HTTP headers sent with every request.
  ///   - encoder: The JSON encoder for request bodies. Defaults to ``JSONEncoder/defaultStorageEncoder``.
  ///   - decoder: The JSON decoder for response bodies. Defaults to ``JSONDecoder/defaultStorageDecoder``.
  ///   - session: The HTTP session used for networking. Defaults to a session backed by `URLSession.shared`.
  ///   - logger: An optional logger. Pass `nil` to disable logging.
  ///   - useNewHostname: When `true`, the storage-specific hostname is used, enabling uploads
  ///     over 50 GB. Read it back as ``usesNewHostname``.
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
    self.usesNewHostname = useNewHostname
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
/// ### Customizing headers
///
/// - ``settingHeader(name:value:)``
///
/// ### Accessing buckets
///
/// - ``from(_:)``
/// - ``vectors``
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

  /// Returns a new client with an additional HTTP header, included in all requests made by the
  /// returned instance and by the bucket instances it creates with ``from(_:)``.
  ///
  /// This method does not change the receiver. Always use the result:
  ///
  /// ```swift
  /// let storage = client.storage.settingHeader(
  ///   name: .init("X-Custom-Header")!, value: "x-custom-header")
  /// ```
  ///
  /// - Parameters:
  ///   - name: The header field. Names match case-insensitively.
  ///   - value: The value of the header field.
  /// - Returns: A new client with the header merged into the configuration's headers.
  public func settingHeader(name: HTTPField.Name, value: String) -> SupabaseStorageClient {
    SupabaseStorageClient(configuration: configuration(settingHeader: name, to: value))
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

/// The top-level Supabase Storage client for managing buckets and files.
///
/// The name this type has in the next major version.
public typealias StorageClient = SupabaseStorageClient

extension SupabaseStorageClient {
  /// Configuration for the Supabase Storage client.
  ///
  /// The name ``StorageClientConfiguration`` has in the next major version.
  public typealias Configuration = StorageClientConfiguration
}
