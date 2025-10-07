import Foundation

public struct StorageClientConfiguration: Sendable {
  public var url: URL
  public var headers: [String: String]
  public let encoder: JSONEncoder
  public let decoder: JSONDecoder
  public let session: StorageHTTPSession
  public let logger: (any SupabaseLogger)?
  public let useNewHostname: Bool

  public init(
    url: URL,
    headers: [String: String],
    session: StorageHTTPSession = .init(),
    logger: (any SupabaseLogger)? = nil,
    useNewHostname: Bool = false
  ) {
    self.url = url
    self.headers = headers
    self.encoder = .defaultStorageEncoder
    self.decoder = .defaultStorageDecoder
    self.session = session
    self.logger = logger
    self.useNewHostname = useNewHostname
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
