import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Storage Bucket API
public class StorageBucketApi: StorageApi {
  /// StorageBucketApi initializer
  /// - Parameters:
  ///   - url: Storage HTTP URL
  ///   - headers: HTTP headers.
  override init(url: String, headers: [String: String], session: StorageHTTPSession) {
    super.init(url: url, headers: headers, session: session)
    self.headers.merge(["Content-Type": "application/json"]) { $1 }
  }

  /// Retrieves the details of all Storage buckets within an existing product.
  public func listBuckets() async throws -> [Bucket] {
    guard let url = URL(string: "\(url)/bucket") else {
      throw StorageError(message: "badURL")
    }

    let response = try await fetch(url: url, method: .get, parameters: nil, headers: headers)
    guard let dict = response as? [[String: Any]] else {
      throw StorageError(message: "failed to parse response")
    }

    return dict.compactMap { Bucket(from: $0) }
  }

  /// Retrieves the details of an existing Storage bucket.
  /// - Parameters:
  ///   - id: The unique identifier of the bucket you would like to retrieve.
  public func getBucket(id: String) async throws -> Bucket {
    guard let url = URL(string: "\(url)/bucket/\(id)") else {
      throw StorageError(message: "badURL")
    }

    let response = try await fetch(url: url, method: .get, parameters: nil, headers: headers)
    guard
      let dict = response as? [String: Any],
      let bucket = Bucket(from: dict)
    else {
      throw StorageError(message: "failed to parse response")
    }

    return bucket
  }

  /// Creates a new Storage bucket
  /// - Parameters:
  ///   - id: A unique identifier for the bucket you are creating.
  ///   - completion: newly created bucket id
  public func createBucket(
    id: String,
    options: BucketOptions = .init()
  ) async throws -> [String: Any] {
    guard let url = URL(string: "\(url)/bucket") else {
      throw StorageError(message: "badURL")
    }

    var params: [String: Any] = [
      "id": id,
      "name": id,
    ]

    params["public"] = options.public
    params["file_size_limit"] = options.fileSizeLimit
    params["allowed_mime_types"] = options.allowedMimeTypes

    let response = try await fetch(
      url: url,
      method: .post,
      parameters: params,
      headers: headers
    )

    guard let dict = response as? [String: Any] else {
      throw StorageError(message: "failed to parse response")
    }

    return dict
  }

  /// Removes all objects inside a single bucket.
  /// - Parameters:
  ///   - id: The unique identifier of the bucket you would like to empty.
  @discardableResult
  public func emptyBucket(id: String) async throws -> [String: Any] {
    guard let url = URL(string: "\(url)/bucket/\(id)/empty") else {
      throw StorageError(message: "badURL")
    }

    let response = try await fetch(url: url, method: .post, parameters: [:], headers: headers)
    guard let dict = response as? [String: Any] else {
      throw StorageError(message: "failed to parse response")
    }
    return dict
  }

  /// Deletes an existing bucket. A bucket can't be deleted with existing objects inside it.
  /// You must first `empty()` the bucket.
  /// - Parameters:
  ///   - id: The unique identifier of the bucket you would like to delete.
  public func deleteBucket(id: String) async throws -> [String: Any] {
    guard let url = URL(string: "\(url)/bucket/\(id)") else {
      throw StorageError(message: "badURL")
    }

    let response = try await fetch(url: url, method: .delete, parameters: [:], headers: headers)
    guard let dict = response as? [String: Any] else {
      throw StorageError(message: "failed to parse response")
    }
    return dict
  }
}
