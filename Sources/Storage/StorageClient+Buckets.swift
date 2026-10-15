import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Bucket-management operations (listing, creating, updating, emptying, and deleting) for
/// ``StorageClient``.
extension StorageClient {
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
    try await api.execute(api.requests.listBuckets(options)).decoded()
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
    var type: BucketType?

    enum CodingKeys: String, CodingKey {
      case id
      case name
      case `public`
      case fileSizeLimit = "file_size_limit"
      case allowedMimeTypes = "allowed_mime_types"
      case type
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
  ///   - options: Options that control visibility, file-size limits, allowed MIME types and the
  ///     bucket type. A `nil` field takes the server default: a private standard bucket with no
  ///     size or type restrictions.
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

    var parameters = BucketParameters(id: id, name: id, options: options)
    parameters.type = options.type
    return try await api.execute(api.requests.createBucket(parameters))
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
  ///   - options: The settings to change. At least one field must be set, and not
  ///     ``BucketOptions/type``: a bucket cannot change type.
  /// - Throws: ``StorageError`` with kind ``StorageError/Kind-swift.struct/invalidRequest`` if no
  ///   field is set or ``BucketOptions/type`` is, or if the bucket does not exist or the caller is not authorized.
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    guard options.type == nil else {
      throw StorageError(
        kind: .invalidRequest, message: "updateBucket cannot change a bucket's type.")
    }
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

  /// Returns the lifecycle policy of a Standard bucket, or `nil` if it has none.
  ///
  /// - Parameter id: The unique identifier of the bucket.
  /// - Throws: ``StorageError`` if lifecycle support is off for the project, the bucket is not a
  ///   Standard bucket, or the caller is not authorized.
  public func lifecycle(forBucket id: String) async throws -> LifecycleConfiguration? {
    do {
      return try await api.execute(api.requests.lifecycle(id, method: .get))
        .decoded(as: LifecycleConfiguration.self)
    } catch let error as StorageError where error.code == .noSuchLifecycleConfiguration {
      return nil
    }
  }

  /// Replaces the lifecycle policy of a Standard bucket.
  ///
  /// The policy replaces whatever the bucket had. To remove it, call
  /// ``deleteLifecycle(forBucket:)``.
  ///
  /// ```swift
  /// try await storage.setLifecycle(
  ///   LifecycleConfiguration(rules: [
  ///     LifecycleRule(noncurrentVersionExpiration: NoncurrentVersionExpiration(noncurrentDays: 30))
  ///   ]),
  ///   forBucket: "documents"
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - configuration: The policy, with 1 to 1000 rules.
  ///   - id: The unique identifier of the bucket.
  /// - Returns: The stored policy, with the identifiers Storage generated for rules that had none.
  /// - Throws: ``StorageError`` if Storage rejects the policy (no rules, more than 1000, or an
  ///   invalid rule), lifecycle support is off, the bucket is not a Standard bucket, or the caller
  ///   is not authorized.
  @discardableResult
  public func setLifecycle(_ configuration: LifecycleConfiguration, forBucket id: String)
    async throws -> LifecycleConfiguration
  {
    try await api.execute(api.requests.setLifecycle(id, configuration))
      .decoded(as: LifecycleConfiguration.self)
  }

  /// Removes the lifecycle policy of a Standard bucket. Succeeds when the bucket has none.
  ///
  /// - Parameter id: The unique identifier of the bucket.
  /// - Throws: ``StorageError`` if lifecycle support is off for the project, the bucket is not a
  ///   Standard bucket, or the caller is not authorized.
  public func deleteLifecycle(forBucket id: String) async throws {
    try await api.execute(api.requests.lifecycle(id, method: .delete))
  }

  /// Purges the CDN cache for every file in a bucket, or in the whole project, so the next
  /// request for each one is served from Storage again. The CDN can take up to 60 seconds to
  /// apply the purge.
  ///
  /// ```swift
  /// try await storage.purgeCache(bucket: "avatars")
  /// try await storage.purgeCache(bucket: nil)  // every bucket
  /// ```
  ///
  /// > Important: This requires the `secret` key and the `purgeCache` tenant feature. On
  /// > self-hosted Storage, a CDN purge endpoint must also be configured, otherwise the request
  /// > fails.
  ///
  /// - Parameters:
  ///   - bucket: The unique identifier of the bucket to purge, or `nil` to purge every bucket.
  ///   - includingTransformations: Pass `true` to also purge the resized and reformatted variants.
  /// - Throws: ``StorageError`` if the caller is not authorized or cache purging is not enabled.
  public func purgeCache(bucket: String?, includingTransformations: Bool = false) async throws {
    try await api.execute(
      api.requests.purgeCache(bucket: bucket, includingTransformations: includingTransformations))
  }
}
