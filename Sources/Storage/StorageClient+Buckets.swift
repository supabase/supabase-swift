import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Bucket-management operations (listing, creating, updating, emptying, and deleting) for
/// ``StorageClient``.
extension StorageClient {
  /// Retrieves the details of all Storage buckets within the project.
  ///
  /// - Returns: An array of ``Bucket`` objects, one for each bucket in the project.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func listBuckets() async throws -> [Bucket] {
    try await api.execute(api.requests.listBuckets()).decoded()
  }

  /// Retrieves the details of an existing Storage bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to retrieve.
  /// - Returns: The ``Bucket`` with the given identifier.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  public func bucket(_ id: String) async throws -> Bucket {
    try await api.execute(api.requests.bucket(id)).decoded()
  }

  /// The create and update body. `nil` fields are left out, so an update changes only what the
  /// caller set.
  struct BucketParameters: Encodable {
    var id: String?
    var name: String?
    var `public`: Bool?
    var fileSizeLimit: ByteCount?
    var allowedMimeTypes: [String]?

    enum CodingKeys: String, CodingKey {
      case id
      case name
      case `public`
      case fileSizeLimit = "file_size_limit"
      case allowedMimeTypes = "allowed_mime_types"
    }

    init(id: String? = nil, name: String? = nil, options: BucketOptions) {
      self.id = id
      self.name = name
      self.public = options.isPublic
      self.fileSizeLimit = options.fileSizeLimit
      self.allowedMimeTypes = options.allowedMimeTypes
    }

    var isEmpty: Bool {
      `public` == nil && fileSizeLimit == nil && allowedMimeTypes == nil
    }
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
  ///   - options: Options that control visibility, file-size limits, and allowed MIME types. A
  ///     `nil` field takes the server default: a private bucket with no size or type restrictions.
  /// - Returns: The bucket name the server stored.
  /// - Throws: ``StorageError`` if a bucket with the same identifier already exists, or if the
  ///   caller is not authorized.
  @discardableResult
  public func createBucket(_ id: String, options: BucketOptions = BucketOptions()) async throws
    -> String
  {
    struct Response: Decodable {
      let name: String
    }

    return try await api.execute(
      api.requests.createBucket(BucketParameters(id: id, name: id, options: options))
    )
    .decoded(as: Response.self)
    .name
  }

  /// Updates an existing Storage bucket's settings.
  ///
  /// Only the fields set on `options` are sent; the others keep their current value.
  ///
  /// ```swift
  /// try await storage.updateBucket(
  ///   "avatars",
  ///   options: BucketOptions(allowedMimeTypes: ["image/png", "image/jpeg"])
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - id: The unique identifier of the bucket to update.
  ///   - options: The settings to change. At least one field must be set.
  /// - Throws: ``StorageError`` with kind ``StorageError/Kind-swift.struct/invalidRequest`` if no
  ///   field is set, or if the bucket does not exist or the caller is not authorized.
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    let parameters = BucketParameters(options: options)
    guard !parameters.isEmpty else {
      throw StorageError(
        kind: .invalidRequest, message: "updateBucket needs at least one field to change.")
    }
    try await api.execute(api.requests.updateBucket(id, parameters))
  }

  /// Removes all objects inside a bucket without deleting the bucket itself.
  ///
  /// > Important: This operation is irreversible. All files in the bucket will be permanently
  /// > deleted.
  ///
  /// - Parameter id: The unique identifier of the bucket to empty.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  public func emptyBucket(_ id: String) async throws {
    try await api.execute(api.requests.emptyBucket(id))
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
    try await api.execute(api.requests.deleteBucket(id))
  }

  /// Purges the CDN cache for every file in a bucket, so the next request for each one is served
  /// from Storage again.
  ///
  /// > Important: This requires the `secret` key. On self-hosted Storage, the `purgeCache` tenant
  /// > feature and a CDN purge endpoint must be configured, otherwise the request fails.
  ///
  /// - Parameters:
  ///   - bucket: The unique identifier of the bucket to purge.
  ///   - transformationsOnly: Pass `true` to purge only the resized and reformatted variants,
  ///     leaving the original files cached.
  /// - Throws: ``StorageError`` if the caller is not authorized or cache purging is not enabled.
  public func purgeCache(bucket: String, transformationsOnly: Bool = false) async throws {
    try await api.execute(
      api.requests.purgeCache(bucket: bucket, key: nil, transformationsOnly: transformationsOnly))
  }
}
