import Foundation
import ConcurrencyExtras

public struct StorageClientConfiguration: Sendable {
  public var url: URL
  public var headers: [String: String]
  public let encoder: JSONEncoder
  public let decoder: JSONDecoder
  public let session: StorageHTTPSession
  public let resumableSessionConfiguration: URLSessionConfiguration
  public let logger: (any SupabaseLogger)?
  public let useNewHostname: Bool

  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder = .defaultStorageEncoder,
    decoder: JSONDecoder = .defaultStorageDecoder,
    session: StorageHTTPSession = .init(),
    resumableSessionConfiguration: URLSessionConfiguration = .background(withIdentifier: "com.supabase.storage.resumable"),
    logger: (any SupabaseLogger)? = nil,
    useNewHostname: Bool = false
  ) {
    self.url = url
    self.headers = headers
    self.encoder = encoder
    self.decoder = decoder
    self.session = session
    self.resumableSessionConfiguration = resumableSessionConfiguration
    self.logger = logger
    self.useNewHostname = useNewHostname
  }
}

public class SupabaseStorageClient: StorageBucketApi, @unchecked Sendable {
  private let resumableStore = LockIsolated<ResumableClientStore?>(nil)

  /// Perform file operation in a bucket.
  /// - Parameter id: The bucket id to operate on.
  /// - Returns: StorageFileApi object
  public func from(_ id: String) -> StorageFileApi {
    let clientStore = resumableStore.withValue {
      if $0 == nil {
        $0 = ResumableClientStore(configuration: configuration)
      }
      return $0!
    }

    return StorageFileApi(bucketId: id, configuration: configuration, clientStore: clientStore)
  }
}
