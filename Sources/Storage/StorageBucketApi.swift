import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Storage Bucket API
public class StorageBucketApi: StorageApi, @unchecked Sendable {
  /// Retrieves the details of all Storage buckets within an existing product.
  public func listBuckets() async throws -> [Bucket] {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket"),
        method: .get
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Retrieves the details of an existing Storage bucket.
  /// - Parameters:
  ///   - id: The unique identifier of the bucket you would like to retrieve.
  public func getBucket(_ id: String) async throws -> Bucket {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)"),
        method: .get
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  struct BucketParameters: Encodable {
    var id: String
    var name: String
    var `public`: Bool
    var fileSizeLimit: String?
    var allowedMimeTypes: [String]?
  }

  /// Creates a new Storage bucket.
  /// - Parameters:
  ///   - id: A unique identifier for the bucket you are creating.
  public func createBucket(_ id: String, options: BucketOptions = .init()) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket"),
        method: .post,
        body: configuration.encoder.encode(
          BucketParameters(
            id: id,
            name: id,
            public: options.public,
            fileSizeLimit: options.fileSizeLimit,
            allowedMimeTypes: options.allowedMimeTypes
          )
        )
      )
    )
  }

  /// Updates a Storage bucket
  /// - Parameters:
  ///   - id: A unique identifier for the bucket you are updating.
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)"),
        method: .put,
        body: configuration.encoder.encode(
          BucketParameters(
            id: id,
            name: id,
            public: options.public,
            fileSizeLimit: options.fileSizeLimit,
            allowedMimeTypes: options.allowedMimeTypes
          )
        )
      )
    )
  }

  /// Removes all objects inside a single bucket.
  /// - Parameters:
  ///   - id: The unique identifier of the bucket you would like to empty.
  public func emptyBucket(_ id: String) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)/empty"),
        method: .post
      )
    )
  }

  /// Deletes an existing bucket. A bucket can't be deleted with existing objects inside it.
  /// You must first `empty()` the bucket.
  /// - Parameters:
  ///   - id: The unique identifier of the bucket you would like to delete.
  public func deleteBucket(_ id: String) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)"),
        method: .delete
      )
    )
  }
}
