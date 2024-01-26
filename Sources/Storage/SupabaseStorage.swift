import _Helpers
import Foundation

public struct StorageClientConfiguration {
  public let url: URL
  public var headers: [String: String]
  public let encoder: JSONEncoder
  public let decoder: JSONDecoder
  public let session: StorageHTTPSession
  public let logger: SupabaseLogger?

  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder = .defaultStorageEncoder,
    decoder: JSONDecoder = .defaultStorageDecoder,
    session: StorageHTTPSession = .init(),
    logger: SupabaseLogger? = nil
  ) {
    self.url = url
    self.headers = headers
    self.encoder = encoder
    self.decoder = decoder
    self.session = session
    self.logger = logger
  }
}

public class SupabaseStorageClient: StorageBucketApi {
  /// Perform file operation in a bucket.
  /// - Parameter id: The bucket id to operate on.
  /// - Returns: StorageFileApi object
  public func from(_ id: String) -> StorageFileApi {
    StorageFileApi(bucketId: id, configuration: configuration)
  }
}
