import Alamofire
import Foundation

public struct StorageClientConfiguration: Sendable {
  public var url: URL
  public var headers: [String: String]
  public let encoder: JSONEncoder
  public let decoder: JSONDecoder
  let http: any HTTPClientType
  @available(
    *, deprecated,
    message: "Use alamofireSession instead. This will be removed in a future version."
  )
  public let session: StorageHTTPSession
  public let logger: (any SupabaseLogger)?
  public let useNewHostname: Bool

  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder = .defaultStorageEncoder,
    decoder: JSONDecoder = .defaultStorageDecoder,
    alamofireSession: Alamofire.Session = .default,
    logger: (any SupabaseLogger)? = nil,
    useNewHostname: Bool = false
  ) {
    self.init(
      url: url,
      headers: headers,
      encoder: encoder,
      decoder: decoder,
      session: nil,
      alamofireSession: alamofireSession,
      logger: logger,
      useNewHostname: useNewHostname
    )
  }

  init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder,
    decoder: JSONDecoder,
    session: StorageHTTPSession?,
    alamofireSession: Alamofire.Session,
    logger: (any SupabaseLogger)?,
    useNewHostname: Bool
  ) {
    self.url = url
    self.headers = headers
    self.encoder = encoder
    self.decoder = decoder
    self.session = session ?? StorageHTTPSession()
    self.logger = logger
    self.useNewHostname = useNewHostname

    var interceptors: [any HTTPClientInterceptor] = []
    if let logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    self.http =
      if let session {
        HTTPClient(fetch: session.fetch, interceptors: interceptors)
      } else {
        AlamofireHTTPClient(session: alamofireSession)
      }
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
