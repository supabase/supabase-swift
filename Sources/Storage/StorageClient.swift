import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct StorageClientConfiguration: Sendable {
  public var url: URL
  public var headers: [String: String]
  public let encoder: JSONEncoder
  public let decoder: JSONDecoder
  public let session: URLSession
  public let logger: (any SupabaseLogger)?
  public let useNewHostname: Bool

  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder? = nil,
    decoder: JSONDecoder? = nil,
    session: URLSession = URLSession(configuration: .default),
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
public final class StorageClient: Sendable {
  public let configuration: StorageClientConfiguration

  package let http: _HTTPClient
  private let usesTokenProvider: Bool

  public convenience init(configuration: StorageClientConfiguration) {
    self.init(configuration: configuration, tokenProvider: nil)
  }

  package init(configuration: StorageClientConfiguration, tokenProvider: TokenProvider?) {
    var configuration = configuration

    let clientInfoHeader = "X-Client-Info"
    let clientInfoHeaders = configuration.headers.keys.filter {
      $0.caseInsensitiveCompare(clientInfoHeader) == .orderedSame
    }

    if let firstClientInfoHeader = clientInfoHeaders.first {
      let clientInfo = configuration.headers[firstClientInfoHeader]
      for duplicateHeader in clientInfoHeaders.dropFirst() {
        configuration.headers.removeValue(forKey: duplicateHeader)
      }

      if firstClientInfoHeader != clientInfoHeader {
        configuration.headers.removeValue(forKey: firstClientInfoHeader)
        configuration.headers[clientInfoHeader] = clientInfo
      }
    } else {
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
    usesTokenProvider = tokenProvider != nil

    http = _HTTPClient(
      host: configuration.url,
      session: configuration.session,
      tokenProvider: tokenProvider
    )
  }

  func mergedHeaders(_ headers: [String: String]? = nil) -> [String: String] {
    var merged = configuration.headers

    for (key, value) in headers ?? [:] {
      if let existingKey = merged.keys.first(where: {
        $0.caseInsensitiveCompare(key) == .orderedSame
      }) {
        merged[existingKey] = value
      } else {
        merged[key] = value
      }
    }

    if usesTokenProvider {
      merged = merged.filter {
        $0.key.caseInsensitiveCompare("Authorization") != .orderedSame
      }
    }

    return merged
  }

  @discardableResult
  func fetchData(
    _ method: HTTPMethod,
    _ path: String,
    query: [String: String]? = nil,
    body: RequestBody? = nil,
    headers: [String: String]? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    let url = configuration.url.appendingPathComponent(path)

    do {
      logRequest(method, url: url)
      let result = try await http.fetchData(
        method,
        url: url,
        query: query,
        body: body,
        headers: mergedHeaders(headers)
      )
      logResponse(result.1, data: result.0)
      return result
    } catch {
      logFailure(error)
      throw translateStorageError(error)
    }
  }

  @discardableResult
  func fetchData(
    _ method: HTTPMethod,
    url: URL,
    query: [String: String]? = nil,
    body: RequestBody? = nil,
    headers: [String: String]? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    do {
      logRequest(method, url: url)
      let result = try await http.fetchData(
        method,
        url: url,
        query: query,
        body: body,
        headers: mergedHeaders(headers)
      )
      logResponse(result.1, data: result.0)
      return result
    } catch {
      logFailure(error)
      throw translateStorageError(error)
    }
  }

  func fetchDecoded<T: Decodable>(
    _ method: HTTPMethod,
    _ path: String,
    query: [String: String]? = nil,
    body: RequestBody? = nil,
    headers: [String: String]? = nil,
    as _: T.Type = T.self
  ) async throws -> T {
    let (data, _) = try await fetchData(method, path, query: query, body: body, headers: headers)
    return try configuration.decoder.decode(T.self, from: data)
  }

  private func translateStorageError(_ error: any Error) -> any Error {
    guard case HTTPClientError.responseError(let response, let data) = error else {
      return error
    }

    if let storageError = try? configuration.decoder.decode(StorageError.self, from: data) {
      return storageError
    }

    return HTTPError(data: data, response: response)
  }

  func logRequest(_ method: HTTPMethod, url: URL) {
    configuration.logger?.verbose(
      "Request: \(method.rawValue) \(url.absoluteString.removingPercentEncoding ?? url.absoluteString)"
    )
  }

  func logResponse(_ response: HTTPURLResponse, data: Data) {
    configuration.logger?.verbose(
      "Response: Status code: \(response.statusCode) Content-Length: \(data.count)"
    )
  }

  func logFailure(_ error: any Error) {
    configuration.logger?.error("Response: Failure \(error)")
  }

  /// Perform file operation in a bucket.
  /// - Parameter id: The bucket id to operate on.
  /// - Returns: StorageFileAPI object
  public func from(_ id: String) -> StorageFileAPI {
    StorageFileAPI(bucketId: id, client: self)
  }

  /// Retrieves the details of all Storage buckets within an existing project.
  public func listBuckets() async throws -> [Bucket] {
    try await fetchDecoded(.get, "bucket")
  }

  /// Retrieves the details of an existing Storage bucket.
  /// - Parameters:
  ///   - id: The unique identifier of the bucket you would like to retrieve.
  public func getBucket(_ id: String) async throws -> Bucket {
    try await fetchDecoded(.get, "bucket/\(id)")
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
    try await fetchData(
      .post,
      "bucket",
      body: .data(
        configuration.encoder.encode(
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
    try await fetchData(
      .put,
      "bucket/\(id)",
      body: .data(
        configuration.encoder.encode(
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
    try await fetchData(.post, "bucket/\(id)/empty")
  }

  /// Deletes an existing bucket. A bucket can't be deleted with existing objects inside it.
  /// You must first `empty()` the bucket.
  /// - Parameters:
  ///   - id: The unique identifier of the bucket you would like to delete.
  public func deleteBucket(_ id: String) async throws {
    try await fetchData(.delete, "bucket/\(id)")
  }
}
