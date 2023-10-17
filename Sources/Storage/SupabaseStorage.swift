public class SupabaseStorageClient: StorageBucketApi {
  /// Storage Client initializer
  /// - Parameters:
  ///   - url: Storage HTTP URL
  ///   - headers: HTTP headers.
  override public init(
    url: String, headers: [String: String], session: StorageHTTPSession = .init()
  ) {
    super.init(url: url, headers: headers, session: session)
  }

  /// Perform file operation in a bucket.
  /// - Parameter id: The bucket id to operate on.
  /// - Returns: StorageFileApi object
  public func from(id: String) -> StorageFileApi {
    StorageFileApi(url: url, headers: headers, bucketId: id, session: session)
  }
}
