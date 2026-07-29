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
/// - ``listBuckets()``
/// - ``getBucket(_:)``
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
    let output = try await openAPIClient.bucketList(.init())
    guard case .ok(let response) = output, case .json(let buckets) = response.body else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
    return buckets.map(Bucket.init(fromGenerated:))
  }

  /// Retrieves the details of an existing Storage bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to retrieve.
  /// - Returns: The ``Bucket`` with the given identifier.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  public func getBucket(_ id: String) async throws -> Bucket {
    let output = try await openAPIClient.bucketGet(.init(path: .init(bucketId: id)))
    guard case .ok(let response) = output, case .json(let bucket) = response.body else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
    return Bucket(fromGenerated: bucket)
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
    let output = try await openAPIClient.bucketCreate(
      .init(
        body: .json(
          .init(
            name: id,
            id: id,
            _public: options.isPublic,
            file_size_limit: options.fileSizeLimit.map { limit in
              if let intValue = Int64(limit) {
                Operations.bucketCreate.Input.Body.jsonPayload.file_size_limitPayload(
                  value1: Int(intValue)
                )
              } else {
                Operations.bucketCreate.Input.Body.jsonPayload.file_size_limitPayload(
                  value2: limit
                )
              }
            },
            allowed_mime_types: options.allowedMimeTypes
          )
        )
      )
    )
    guard case .ok = output else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
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
    let output = try await openAPIClient.bucketUpdate(
      .init(
        path: .init(bucketId: id),
        body: .json(
          .init(
            _public: options.isPublic,
            file_size_limit: options.fileSizeLimit.map { limit in
              if let intValue = Int64(limit) {
                Operations.bucketUpdate.Input.Body.jsonPayload.file_size_limitPayload(
                  value1: Int(intValue)
                )
              } else {
                Operations.bucketUpdate.Input.Body.jsonPayload.file_size_limitPayload(
                  value2: limit
                )
              }
            },
            allowed_mime_types: options.allowedMimeTypes
          )
        )
      )
    )
    guard case .ok = output else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
  }

  /// Removes all objects inside a bucket without deleting the bucket itself.
  ///
  /// > Important: This operation is irreversible. All files in the bucket will be permanently
  /// > deleted.
  ///
  /// - Parameter id: The unique identifier of the bucket to empty.
  /// - Throws: ``StorageError`` if the bucket does not exist or the caller is not authorized.
  public func emptyBucket(_ id: String) async throws {
    let output = try await openAPIClient.bucketEmpty(.init(path: .init(bucketId: id)))
    guard case .ok = output else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
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
    let output = try await openAPIClient.bucketDelete(.init(path: .init(bucketId: id)))
    guard case .ok = output else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
  }
}
