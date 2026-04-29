import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Configuration for ``StorageClient``.
///
/// Pass an instance to ``StorageClient/init(url:configuration:)`` to customise the HTTP layer,
/// request headers, and optional diagnostics logging.
///
/// ## Example
///
/// ```swift
/// let config = StorageClientConfiguration(
///   headers: [
///     "apikey": "<anon-key>",
///     "Authorization": "Bearer <access-token>"
///   ],
///   logger: myLogger
/// )
/// let storage = StorageClient(
///   url: URL(string: "https://<project-ref>.supabase.co/storage/v1")!,
///   configuration: config
/// )
/// ```
public struct StorageClientConfiguration: Sendable {
  /// HTTP headers included in every request made by the client.
  ///
  /// An `X-Client-Info` header is appended automatically if not already present. The
  /// `Authorization` header set here is used unless a `TokenProvider` is configured via the
  /// package-level initialiser, in which case it is refreshed automatically.
  public var headers: [String: String]

  /// The `URLSession` used for all HTTP requests.
  ///
  /// Defaults to a session created with `.default` configuration.
  public let session: URLSession

  /// An optional logger that receives verbose request and response diagnostics.
  ///
  /// Implement `SupabaseLogger` and supply it here to observe all storage HTTP traffic.
  /// Pass `nil` (the default) to disable logging.
  public let logger: (any SupabaseLogger)?

  /// When `true`, rewrites legacy Supabase hostnames to use the dedicated storage subdomain,
  /// which disables request buffering and enables uploads larger than 50 GB.
  ///
  /// `<project-ref>.supabase.co` is rewritten to `<project-ref>.storage.supabase.co`.
  /// Defaults to `false`.
  public let useNewHostname: Bool

  /// Creates a ``StorageClientConfiguration``.
  ///
  /// - Parameters:
  ///   - headers: HTTP headers included in every request. An `X-Client-Info` header is added
  ///     automatically when absent.
  ///   - session: The `URLSession` to use. Defaults to a `.default` session.
  ///   - logger: An optional `SupabaseLogger` for request/response diagnostics. Defaults to `nil`.
  ///   - useNewHostname: When `true`, rewrites the host to the dedicated storage subdomain for
  ///     large-file upload support. Defaults to `false`.
  public init(
    headers: [String: String],
    session: URLSession = URLSession(configuration: .default),
    logger: (any SupabaseLogger)? = nil,
    useNewHostname: Bool = false
  ) {
    self.headers = headers
    self.session = session
    self.logger = logger
    self.useNewHostname = useNewHostname
  }
}

/// A client for managing Supabase Storage buckets and files.
///
/// `StorageClient` is the entry point for all Storage operations. Use it to manage buckets
/// directly, or call ``from(_:)`` to obtain a ``StorageFileAPI`` for file operations within a
/// specific bucket.
///
/// ## Basic usage
///
/// ```swift
/// let storage = StorageClient(
///   url: URL(string: "https://<project-ref>.supabase.co/storage/v1")!,
///   configuration: StorageClientConfiguration(
///     headers: ["apikey": "<anon-key>", "Authorization": "Bearer <access-token>"]
///   )
/// )
///
/// // Create a bucket
/// try await storage.createBucket("avatars", options: BucketOptions(public: true))
///
/// // Upload a file
/// try await storage.from("avatars").upload("user.png", data: imageData)
///
/// // Get public URL
/// let url = try storage.from("avatars").getPublicURL(path: "user.png")
/// ```
///
/// When using ``SupabaseClient``, the storage client is pre-configured and accessible via
/// `supabase.storage`.
///
/// - Note: All state is set at initialisation and never mutated, making `StorageClient` safe to
///   share across concurrency boundaries.
public final class StorageClient: Sendable {
  /// The base URL of the Storage API, e.g. `https://<project-ref>.supabase.co/storage/v1`.
  public let url: URL

  /// The configuration used by this client, including headers, session, and logging preferences.
  public let configuration: StorageClientConfiguration

  package let http: _HTTPClient
  private let usesTokenProvider: Bool

  let encoder: JSONEncoder = {
    let encoder = JSONEncoder.supabase()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  let decoder = JSONDecoder.supabase()

  /// Creates a `StorageClient` for standalone use (without a ``SupabaseClient``).
  ///
  /// Use this initialiser when you want to interact with Supabase Storage independently, without
  /// the broader Supabase client stack. For most apps, create a ``SupabaseClient`` and access
  /// its `storage` property instead.
  ///
  /// - Parameters:
  ///   - url: The base URL for the Storage endpoint,
  ///     e.g. `https://<project-ref>.supabase.co/storage/v1`.
  ///   - configuration: The client configuration, including authentication headers, URL session,
  ///     and logging preferences.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let storage = StorageClient(
  ///   url: URL(string: "https://<project-ref>.supabase.co/storage/v1")!,
  ///   configuration: StorageClientConfiguration(
  ///     headers: ["apikey": "<anon-key>", "Authorization": "Bearer <access-token>"]
  ///   )
  /// )
  /// ```
  public convenience init(url: URL, configuration: StorageClientConfiguration) {
    self.init(url: url, configuration: configuration, tokenProvider: nil)
  }

  package init(url: URL, configuration: StorageClientConfiguration, tokenProvider: TokenProvider?) {
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

    var resolvedURL = url

    // if legacy uri is used, replace with new storage host (disables request buffering to allow > 50GB uploads)
    // "project-ref.supabase.co" becomes "project-ref.storage.supabase.co"
    if configuration.useNewHostname == true {
      guard
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let host = components.host
      else {
        fatalError("Client initialized with invalid URL: \(url)")
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

      resolvedURL = components.url!
    }

    self.url = resolvedURL
    self.configuration = configuration
    usesTokenProvider = tokenProvider != nil

    http = _HTTPClient(
      host: resolvedURL,
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
    let url = self.url.appendingPathComponent(path)

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
    return try decoder.decode(T.self, from: data)
  }

  private func translateStorageError(_ error: any Error) -> any Error {
    guard case HTTPClientError.responseError(let response, let data) = error else {
      return error
    }

    if let storageError = try? decoder.decode(StorageError.self, from: data) {
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

  /// Returns a ``StorageFileAPI`` scoped to the given bucket.
  ///
  /// All file operations — upload, download, list, delete, signed URLs — are performed through
  /// the returned ``StorageFileAPI`` instance.
  ///
  /// - Parameter id: The unique identifier of the bucket to operate on.
  /// - Returns: A ``StorageFileAPI`` bound to the specified bucket.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let avatarsBucket = storage.from("avatars")
  /// let data = try await avatarsBucket.download(path: "user-123/photo.png")
  /// ```
  public func from(_ id: String) -> StorageFileAPI {
    StorageFileAPI(bucketId: id, client: self)
  }

  /// Retrieves the details of all Storage buckets within the project.
  ///
  /// - Returns: An array of ``Bucket`` values, one per existing bucket.
  /// - Throws: ``StorageError`` if the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let buckets = try await storage.listBuckets()
  /// for bucket in buckets {
  ///   print("\(bucket.id) — public: \(bucket.isPublic)")
  /// }
  /// ```
  public func listBuckets() async throws -> [Bucket] {
    try await fetchDecoded(.get, "bucket")
  }

  /// Retrieves the details of a single Storage bucket.
  ///
  /// - Parameter id: The unique identifier of the bucket to retrieve.
  /// - Returns: The matching ``Bucket``.
  /// - Throws: ``StorageError`` if the bucket does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let bucket = try await storage.getBucket("avatars")
  /// print("Bucket is \(bucket.isPublic ? "public" : "private")")
  /// ```
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
  ///
  /// - Parameters:
  ///   - id: A unique identifier for the bucket. Used as both the ID and display name.
  ///   - options: Visibility, file-size limit, and MIME-type restrictions for the bucket.
  ///     Defaults to a private bucket with no restrictions.
  /// - Throws: ``StorageError`` if the bucket already exists or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Create a private bucket restricted to images ≤ 5 MB
  /// try await storage.createBucket(
  ///   "avatars",
  ///   options: BucketOptions(
  ///     public: false,
  ///     fileSizeLimit: "5242880",
  ///     allowedMimeTypes: ["image/*"]
  ///   )
  /// )
  /// ```
  public func createBucket(_ id: String, options: BucketOptions = .init())
    async throws
  {
    try await fetchData(
      .post,
      "bucket",
      body: .data(
        encoder.encode(
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

  /// Updates the configuration of an existing Storage bucket.
  ///
  /// - Parameters:
  ///   - id: The unique identifier of the bucket to update.
  ///   - options: The new bucket options. All fields replace the existing configuration.
  /// - Throws: ``StorageError`` if the bucket does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Make an existing bucket public
  /// try await storage.updateBucket("avatars", options: BucketOptions(public: true))
  /// ```
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    try await fetchData(
      .put,
      "bucket/\(id)",
      body: .data(
        encoder.encode(
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

  /// Removes all objects inside a bucket without deleting the bucket itself.
  ///
  /// This is a prerequisite for ``deleteBucket(_:)``, which cannot remove a bucket that
  /// contains objects.
  ///
  /// - Parameter id: The unique identifier of the bucket to empty.
  /// - Throws: ``StorageError`` if the bucket does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// try await storage.emptyBucket("temp-uploads")
  /// try await storage.deleteBucket("temp-uploads")
  /// ```
  public func emptyBucket(_ id: String) async throws {
    try await fetchData(.post, "bucket/\(id)/empty")
  }

  /// Deletes an existing Storage bucket.
  ///
  /// The bucket must be empty before it can be deleted. Call ``emptyBucket(_:)`` first to
  /// remove all objects, or delete individual files using ``StorageFileAPI/remove(paths:)``.
  ///
  /// - Parameter id: The unique identifier of the bucket to delete.
  /// - Throws: ``StorageError`` if the bucket is not empty, does not exist, or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// try await storage.emptyBucket("old-bucket")
  /// try await storage.deleteBucket("old-bucket")
  /// ```
  public func deleteBucket(_ id: String) async throws {
    try await fetchData(.delete, "bucket/\(id)")
  }
}
