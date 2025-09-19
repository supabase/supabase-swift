import Alamofire
import Foundation

public struct StorageClientConfiguration: Sendable {
  public var url: URL
  public var headers: [String: String]
  public let encoder: JSONEncoder
  public let decoder: JSONDecoder
  public let session: Alamofire.Session
  public let logger: SupabaseLogger?
  public let useNewHostname: Bool
  public let uploadRetryAttempts: Int
  public let uploadTimeoutInterval: TimeInterval

  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder(),
    session: Alamofire.Session = .default,
    logger: SupabaseLogger? = nil,
    useNewHostname: Bool = false,
    uploadRetryAttempts: Int = 3,
    uploadTimeoutInterval: TimeInterval = 300.0
  ) {
    self.url = url
    self.headers = headers
    self.encoder = encoder
    self.decoder = decoder
    self.session = session
    self.logger = logger
    self.useNewHostname = useNewHostname
    self.uploadRetryAttempts = uploadRetryAttempts
    self.uploadTimeoutInterval = uploadTimeoutInterval
  }
}

public class SupabaseStorageClient: StorageBucketApi, @unchecked Sendable {
  /// Perform file operation in a bucket.
  /// - Parameter id: The bucket id to operate on.
  /// - Returns: StorageFileApi object
  public func from(_ id: String) -> StorageFileApi {
    StorageFileApi(bucketId: id, configuration: configuration)
  }
}
