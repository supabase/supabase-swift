import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Storage API for bucket management operations.
///
/// ``StorageBucketApi`` provides methods to list, create, update, empty, and delete Storage
/// buckets. It is the superclass of ``SupabaseStorageClient``.
///
/// > Note: This class is `@unchecked Sendable` and inherits the thread-safe design of
/// > ``StorageApi``. No additional mutable state is introduced.
///
/// ## Topics
///
/// ### Listing and inspecting buckets
///
/// - ``listBuckets(options:)``
/// - ``listBuckets()``
/// - ``bucket(_:)``
///
/// ### Creating and updating buckets
///
/// - ``createBucket(_:options:)``
/// - ``updateBucket(_:options:)``
///
/// ### Removing buckets
///
/// - ``emptyBucket(_:)``
/// - ``deleteBucket(_:)``
public class StorageBucketApi: StorageApi, @unchecked Sendable {
  /// Retrieves the details of all Storage buckets within the project.
  ///
  /// - Returns: An array of ``Bucket`` objects, one for each bucket in the project.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func listBuckets() async throws -> [Bucket] {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket"),
        method: .get
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Retrieves the Storage buckets within the project.
  ///
  /// ```swift
  /// let recent = try await storage.listBuckets(
  ///   options: BucketListOptions(limit: 10, sortBy: .createdAt, order: .descending))
  /// ```
  ///
  /// - Parameter options: Paging, sort and a name filter. Defaults to every bucket.
  /// - Returns: The buckets the caller can see.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func listBuckets(options: BucketListOptions = BucketListOptions()) async throws
    -> [Bucket]
  {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket"),
        method: .get,
        query: options.queryItems
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Retrieves the details of an existing Storage bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to retrieve.
  /// - Returns: The ``Bucket`` with the given identifier.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  public func bucket(_ id: String) async throws -> Bucket {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)"),
        method: .get
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Retrieves the details of an existing Storage bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to retrieve.
  /// - Returns: The ``Bucket`` with the given identifier.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  @available(*, deprecated, renamed: "bucket(_:)")
  public func getBucket(_ id: String) async throws -> Bucket {
    try await bucket(id)
  }

  /// The body of the create and update requests made with ``CreateBucketOptions`` and
  /// ``UpdateBucketOptions``. `nil` fields are left out, so an update changes only what the
  /// caller set.
  struct OptionalBucketParameters: Encodable {
    var id: String?
    var name: String?
    var `public`: Bool?
    var fileSizeLimit: ByteCount?
    var allowedMimeTypes: [String]?
    var type: BucketType?
    var versioningStatus: String?

    enum CodingKeys: String, CodingKey {
      case id
      case name
      case `public`
      case fileSizeLimit = "file_size_limit"
      case allowedMimeTypes = "allowed_mime_types"
      case type
      case versioningStatus = "versioning_status"
    }

    init(id: String, options: CreateBucketOptions) {
      self.id = id
      self.name = id
      self.public = options.isPublic
      self.fileSizeLimit = options.fileSizeLimit
      self.allowedMimeTypes = options.allowedMimeTypes
      self.type = options.type
      self.versioningStatus = options.versioningStatus?.rawValue
    }

    init(options: UpdateBucketOptions) {
      self.public = options.isPublic
      self.fileSizeLimit = options.fileSizeLimit
      self.allowedMimeTypes = options.allowedMimeTypes
      self.versioningStatus = options.versioningStatus?.rawValue
    }

    var isEmpty: Bool {
      `public` == nil && fileSizeLimit == nil && allowedMimeTypes == nil && versioningStatus == nil
    }
  }

  /// Creates a new Storage bucket.
  ///
  /// ```swift
  /// try await storage.createBucket(
  ///   "avatars",
  ///   options: CreateBucketOptions(isPublic: true, fileSizeLimit: .megabytes(5))
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - id: A unique identifier for the bucket. This also becomes the bucket name.
  ///   - options: Options that control visibility, file-size limits, allowed MIME types, the
  ///     bucket type and versioning. A `nil` field takes the server default: a private standard
  ///     bucket with no size or type restrictions and versioning off.
  /// - Returns: The bucket name the server stored.
  /// - Throws: ``StorageError`` if a bucket with the same identifier already exists, or if the
  ///   caller is not authorized.
  @_disfavoredOverload
  @discardableResult
  public func createBucket(
    _ id: String, options: CreateBucketOptions = CreateBucketOptions()
  ) async throws -> String {
    struct Response: Decodable {
      let name: String
    }

    return try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket"),
        method: .post,
        body: configuration.encoder.encode(OptionalBucketParameters(id: id, options: options))
      )
    )
    .decoded(as: Response.self, decoder: configuration.decoder)
    .name
  }

  /// Updates an existing Storage bucket's settings.
  ///
  /// Only the fields set on `options` are sent; the others keep their current value.
  ///
  /// ```swift
  /// try await storage.updateBucket(
  ///   "avatars",
  ///   options: UpdateBucketOptions(allowedMimeTypes: ["image/png", "image/jpeg"])
  /// )
  /// try await storage.updateBucket(
  ///   "avatars", options: UpdateBucketOptions(versioningStatus: .suspended))
  /// ```
  ///
  /// - Parameters:
  ///   - id: The unique identifier of the bucket to update.
  ///   - options: The settings to change. At least one field must be set.
  /// - Throws: ``StorageError`` with kind ``StorageError/Kind-swift.struct/invalidRequest`` if no
  ///   field is set, or if the bucket does not exist or the caller is not authorized.
  @_disfavoredOverload
  public func updateBucket(_ id: String, options: UpdateBucketOptions) async throws {
    let parameters = OptionalBucketParameters(options: options)
    guard !parameters.isEmpty else {
      throw StorageError(
        kind: .invalidRequest, message: "updateBucket needs at least one field to change.")
    }
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)"),
        method: .put,
        body: configuration.encoder.encode(parameters)
      )
    )
  }

  struct BucketParameters: Encodable {
    var id: String
    var name: String
    var `public`: Bool
    var fileSizeLimit: StorageByteCount?
    var allowedMimeTypes: [String]?
  }

  /// Creates a new Storage bucket.
  ///
  /// ```swift
  /// try await storage.createBucket(
  ///   "avatars",
  ///   options: BucketOptions(isPublic: true, fileSizeLimit: .megabytes(5))
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - id: A unique identifier for the bucket. This also becomes the bucket name.
  ///   - options: Options that control visibility, file-size limits, and allowed MIME types.
  ///     Defaults to a private bucket with no size or type restrictions.
  /// - Throws: ``StorageError`` if a bucket with the same identifier already exists, or if the
  ///   caller is not authorized.
  @available(
    *, deprecated, message: "Use createBucket(_:options:) with CreateBucketOptions instead."
  )
  public func createBucket(_ id: String, options: BucketOptions = BucketOptions(isPublic: false))
    async throws
  {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket"),
        method: .post,
        body: configuration.encoder.encode(
          BucketParameters(
            id: id,
            name: id,
            public: options.isPublic,
            fileSizeLimit: options.fileSizeLimit.map { StorageByteCount(stringLiteral: $0) },
            allowedMimeTypes: options.allowedMimeTypes
          )
        )
      )
    )
  }

  /// Updates an existing Storage bucket's settings.
  ///
  /// ```swift
  /// try await storage.updateBucket(
  ///   "avatars",
  ///   options: BucketOptions(isPublic: false, allowedMimeTypes: ["image/png", "image/jpeg"])
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - id: The unique identifier of the bucket to update.
  ///   - options: The new options to apply to the bucket.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  @available(
    *, deprecated,
    message:
      "Use updateBucket(_:options:) with UpdateBucketOptions instead. It sends only the fields you set."
  )
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)"),
        method: .put,
        body: configuration.encoder.encode(
          BucketParameters(
            id: id,
            name: id,
            public: options.isPublic,
            fileSizeLimit: options.fileSizeLimit.map { StorageByteCount(stringLiteral: $0) },
            allowedMimeTypes: options.allowedMimeTypes
          )
        )
      )
    )
  }

  /// Removes all objects inside a bucket without deleting the bucket itself.
  ///
  /// > Important: This operation is irreversible. All files in the bucket will be permanently
  /// > deleted.
  ///
  /// - Parameter id: The unique identifier of the bucket to empty.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  public func emptyBucket(_ id: String) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)/empty"),
        method: .post
      )
    )
  }

  /// Deletes an existing bucket.
  ///
  /// > Important: A bucket cannot be deleted while it contains objects. Call ``emptyBucket(_:)``
  /// > first to remove all files, then delete the bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to delete.
  /// - Throws: ``StorageError`` if the bucket is not empty, does not exist, or the caller is not
  ///   authorized.
  public func deleteBucket(_ id: String) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)"),
        method: .delete
      )
    )
  }
}
