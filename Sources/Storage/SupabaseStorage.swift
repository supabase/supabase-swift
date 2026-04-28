import Foundation
import HTTPTypes
import Helpers

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
    encoder: JSONEncoder? = nil,
    decoder: JSONDecoder? = nil,
    session: StorageHTTPSession = .init(),
    logger: (any SupabaseLogger)? = nil,
    useNewHostname: Bool = false
  ) {
    self.url = url
    self.headers = headers
    self.encoder =
      encoder
      ?? {
        let encoder = JSONEncoder.supabase()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
      }()
    self.decoder = decoder ?? .supabase()
    self.session = session
    self.logger = logger
    self.useNewHostname = useNewHostname
  }
}

/// Supabase Storage client for managing buckets and files.
///
/// - Note: Thread Safety: Inherits immutable design from `StorageApi`. All state is set at
///   initialization and never mutated.
public final class SupabaseStorageClient {
  public let configuration: StorageClientConfiguration

  private let http: any HTTPClientType
  let httpClient: _HTTPClient

  public init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }

    // if legacy uri is used, replace with new storage host (disables request buffering to allow > 50GB uploads)
    // "project-ref.supabase.co" becomes "project-ref.storage.supabase.co"
    if configuration.useNewHostname == true {
      guard
        var components = URLComponents(
          url: configuration.url,
          resolvingAgainstBaseURL: false
        ),
        let host = components.host
      else {
        fatalError("Client initialized with invalid URL: \(configuration.url)")
      }

      let regex = try! NSRegularExpression(pattern: "supabase.(co|in|red)$")

      let isSupabaseHost =
        regex.firstMatch(
          in: host,
          range: NSRange(location: 0, length: host.utf16.count)
        ) != nil

      if isSupabaseHost, !host.contains("storage.supabase.") {
        components.host = host.replacingOccurrences(
          of: "supabase.",
          with: "storage.supabase."
        )
      }

      configuration.url = components.url!
    }

    self.configuration = configuration

    var interceptors: [any HTTPClientInterceptor] = []
    if let logger = configuration.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    http = HTTPClient(
      fetch: configuration.session.fetch,
      interceptors: interceptors
    )
    httpClient = _HTTPClient(
      host: configuration.url,
      session: URLSession(configuration: .default),
      tokenProvider: { nil }  // TODO: Support auth tokens in Storage API (requires changes to StorageClientConfiguration and StorageApi init methods
    )
  }

  @discardableResult
  func execute(_ request: Helpers.HTTPRequest) async throws
    -> Helpers.HTTPResponse
  {
    var request = request
    request.headers = HTTPFields(configuration.headers).merging(
      with: request.headers
    )

    let response = try await http.send(request)

    guard (200..<300).contains(response.statusCode) else {
      if let error = try? configuration.decoder.decode(
        StorageError.self,
        from: response.data
      ) {
        throw error
      }

      throw HTTPError(
        data: response.data,
        response: response.underlyingResponse
      )
    }

    return response
  }

  /// Perform file operation in a bucket.
  /// - Parameter id: The bucket id to operate on.
  /// - Returns: StorageFileAPI object
  public func from(_ id: String) -> StorageFileAPI {
    StorageFileAPI(bucketId: id, client: self)
  }

  /// Retrieves the details of all Storage buckets within an existing project.
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
    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("bucket/\(id)"),
        method: .get
      )
    )
    return try response.decoded(decoder: configuration.decoder)
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
  ///   - options: Options for creating the bucket.
  public func createBucket(_ id: String, options: BucketOptions = .init())
    async throws
  {
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

  /// Updates a Storage bucket.
  /// - Parameters:
  ///   - id: A unique identifier for the bucket you are updating.
  ///   - options: Options for updating the bucket.
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
