import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Bucket-management operations (listing, creating, updating, emptying, and deleting) for
/// ``SupabaseStorageClient``.
extension SupabaseStorageClient {
  /// Retrieves the details of all Storage buckets within the project.
  ///
  /// - Returns: An array of ``Bucket`` objects, one for each bucket in the project.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func listBuckets() async throws -> [Bucket] {
    try await api.execute(
      HTTPRequest(
        method: .get,
        url: api.configuration.url.appendingPathComponent("bucket")
      )
    )
    .decoded(decoder: api.configuration.decoder)
  }

  /// Retrieves the details of an existing Storage bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to retrieve.
  /// - Returns: The ``Bucket`` with the given identifier.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  public func bucket(_ id: String) async throws -> Bucket {
    try await api.execute(
      HTTPRequest(
        method: .get,
        url: api.configuration.url.appendingPathComponent("bucket/\(id)")
      )
    )
    .decoded(decoder: api.configuration.decoder)
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
  public func createBucket(_ id: String, options: BucketOptions = BucketOptions(isPublic: false))
    async throws
  {
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: api.configuration.url.appendingPathComponent("bucket")
      ),
      body: api.configuration.encoder.encode(
        BucketParameters(
          id: id,
          name: id,
          public: options.isPublic,
          fileSizeLimit: options.fileSizeLimit.map { StorageByteCount(stringLiteral: $0) },
          allowedMimeTypes: options.allowedMimeTypes
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
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    try await api.execute(
      HTTPRequest(
        method: .put,
        url: api.configuration.url.appendingPathComponent("bucket/\(id)")
      ),
      body: api.configuration.encoder.encode(
        BucketParameters(
          id: id,
          name: id,
          public: options.isPublic,
          fileSizeLimit: options.fileSizeLimit.map { StorageByteCount(stringLiteral: $0) },
          allowedMimeTypes: options.allowedMimeTypes
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
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: api.configuration.url.appendingPathComponent("bucket/\(id)/empty")
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
    try await api.execute(
      HTTPRequest(
        method: .delete,
        url: api.configuration.url.appendingPathComponent("bucket/\(id)")
      )
    )
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
      HTTPRequest(
        method: .delete,
        url: api.configuration.url.appendingPathComponent("cdn/\(bucket)"),
        query: transformationsOnly ? [URLQueryItem(name: "transformations", value: "true")] : []
      )
    )
  }
}
