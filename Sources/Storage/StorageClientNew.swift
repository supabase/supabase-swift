import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Phantom type

/// Phantom type that constrains ``StorageAPI`` to bucket-scoped file operations.
public enum BucketScope {}

// MARK: - StorageClient

/// A Supabase Storage client for managing buckets and invoking file operations.
///
/// `StorageClient` is a value type — all properties are immutable after initialisation.
/// Obtain a scoped file-operations handle by calling ``from(_:)``:
///
/// ```swift
/// let storage = StorageClient(url: url, headers: headers)
///
/// // Bucket management
/// let buckets = try await storage.listBuckets()
///
/// // File operations scoped to a bucket
/// let data = try await storage.from("avatars").download(path: "user/profile.png")
/// ```
public struct StorageClient: Sendable {
  let configuration: StorageClientConfiguration
  let tokenProvider: TokenProvider?

  /// Creates a `StorageClient` for standalone use.
  ///
  /// - Parameters:
  ///   - url: The Storage endpoint URL, e.g. `https://<project-ref>.supabase.co/storage/v1`.
  ///   - headers: Additional headers included in every request.
  ///   - session: The HTTP session used to perform requests. Defaults to `URLSession.shared`.
  public init(
    url: URL,
    headers: [String: String] = [:],
    session: StorageHTTPSession = .init()
  ) {
    self.init(
      configuration: StorageClientConfiguration(url: url, headers: headers, session: session),
      tokenProvider: nil
    )
  }

  package init(
    configuration: StorageClientConfiguration,
    tokenProvider: TokenProvider?
  ) {
    self.configuration = configuration
    self.tokenProvider = tokenProvider
  }

  // MARK: - Scoped file operations

  /// Returns a handle for performing file operations in `bucket`.
  ///
  /// - Parameter bucket: The bucket identifier.
  /// - Returns: A ``StorageAPI`` scoped to bucket-level file operations.
  public func from(_ bucket: String) -> StorageAPI<BucketScope> {
    StorageAPI(bucket: bucket, client: self, additionalHeaders: [:])
  }

  // MARK: - Bucket management

  /// Retrieves all buckets in the project.
  public func listBuckets() async throws -> [Bucket] {
    // TODO: implement using _HTTPClient
    fatalError("not yet implemented")
  }

  /// Retrieves a single bucket by identifier.
  /// - Parameter id: The bucket identifier.
  public func getBucket(_ id: String) async throws -> Bucket {
    fatalError("not yet implemented")
  }

  /// Creates a new bucket.
  /// - Parameters:
  ///   - id: A unique identifier for the new bucket.
  ///   - options: Configuration options for the bucket.
  public func createBucket(_ id: String, options: BucketOptions = .init()) async throws {
    fatalError("not yet implemented")
  }

  /// Updates an existing bucket.
  /// - Parameters:
  ///   - id: The identifier of the bucket to update.
  ///   - options: The new configuration to apply.
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    fatalError("not yet implemented")
  }

  /// Removes all objects in a bucket without deleting the bucket itself.
  /// - Parameter id: The bucket identifier.
  public func emptyBucket(_ id: String) async throws {
    fatalError("not yet implemented")
  }

  /// Deletes a bucket and all its objects.
  /// - Parameter id: The bucket identifier.
  public func deleteBucket(_ id: String) async throws {
    fatalError("not yet implemented")
  }
}

// MARK: - StorageAPI

/// A handle for performing file operations scoped to a specific bucket.
///
/// Obtain an instance via ``StorageClient/from(_:)``. Use ``setting(_:to:)`` to attach
/// per-request headers without mutating the original value:
///
/// ```swift
/// let api = storage.from("avatars")
///
/// // Per-request header override
/// let data = try await api
///   .setting("Cache-Control", to: "no-store")
///   .download(path: "user/profile.png")
/// ```
public struct StorageAPI<Scope>: Sendable {
  let bucket: String
  let client: StorageClient
  let additionalHeaders: [String: String]

  /// Returns a copy of this value with `header` set to `value`.
  ///
  /// The returned `StorageAPI` carries the extra header for all operations invoked on it.
  /// The original value is unchanged.
  ///
  /// - Parameters:
  ///   - header: The HTTP header field name.
  ///   - value: The value to set.
  public func setting(_ header: String, to value: String) -> Self {
    let copy = self
    var headers = copy.additionalHeaders
    headers[header] = value
    return StorageAPI(bucket: copy.bucket, client: copy.client, additionalHeaders: headers)
  }
}

// MARK: - File operations (BucketScope)

extension StorageAPI where Scope == BucketScope {

  // MARK: Upload

  /// Uploads `data` to `path` in the bucket.
  /// - Parameters:
  ///   - path: The destination path inside the bucket (e.g. `"folder/file.png"`).
  ///   - data: The file contents to upload.
  ///   - options: Upload options such as content type and cache control.
  /// - Returns: Metadata for the uploaded object.
  @discardableResult
  public func upload(_ path: String, data: Data, options: FileOptions = FileOptions()) async throws
    -> FileUploadResponse
  {
    fatalError("not yet implemented")
  }

  /// Uploads the file at `fileURL` to `path` in the bucket.
  /// - Parameters:
  ///   - path: The destination path inside the bucket.
  ///   - fileURL: A local URL pointing to the file to upload.
  ///   - options: Upload options such as content type and cache control.
  /// - Returns: Metadata for the uploaded object.
  @discardableResult
  public func upload(
    _ path: String, fileURL: URL, options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    fatalError("not yet implemented")
  }

  /// Uploads a large file at `fileURL` using multipart upload.
  ///
  /// Prefer this method for files larger than a few MB; it resumes partial uploads and is more
  /// resilient to network interruptions than the single-part ``upload(_:fileURL:options:)``.
  ///
  /// - Parameters:
  ///   - fileURL: A local URL pointing to the file to upload.
  ///   - path: The destination path inside the bucket.
  ///   - options: Upload options such as content type and cache control.
  /// - Returns: Metadata for the uploaded object.
  @available(macOS 10.15.4, *)
  @discardableResult
  public func uploadFile(
    _ fileURL: URL, to path: String, options: FileOptions? = nil
  ) async throws -> FileUploadResponse {
    fatalError("not yet implemented")
  }

  // MARK: Update

  /// Replaces an existing object at `path` with `data`.
  @discardableResult
  public func update(_ path: String, data: Data, options: FileOptions = FileOptions()) async throws
    -> FileUploadResponse
  {
    fatalError("not yet implemented")
  }

  /// Replaces an existing object at `path` with the file at `fileURL`.
  @discardableResult
  public func update(
    _ path: String, fileURL: URL, options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    fatalError("not yet implemented")
  }

  // MARK: Move / Copy

  /// Moves an object from `source` to `destination` within the bucket (or across buckets).
  /// - Parameters:
  ///   - source: The current path of the object.
  ///   - destination: The target path.
  ///   - options: Optional destination bucket override.
  public func move(
    from source: String, to destination: String, options: DestinationOptions? = nil
  ) async throws {
    fatalError("not yet implemented")
  }

  /// Copies an object from `source` to `destination`.
  /// - Returns: The full path of the newly created copy.
  @discardableResult
  public func copy(
    from source: String, to destination: String, options: DestinationOptions? = nil
  ) async throws -> String {
    fatalError("not yet implemented")
  }

  // MARK: Signed URLs

  /// Creates a signed URL for `path` that expires after `expiresIn` seconds.
  ///
  /// - Parameters:
  ///   - path: The object path inside the bucket.
  ///   - expiresIn: Seconds until the URL expires.
  ///   - download: An optional filename to trigger a browser download.
  ///   - transform: Optional image transformation parameters.
  ///   - cacheNonce: Optional nonce for CDN cache-busting.
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: String? = nil,
    transform: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) async throws -> URL {
    fatalError("not yet implemented")
  }

  /// Creates a signed URL for `path`, optionally triggering a download with `Content-Disposition`.
  ///
  /// - Parameters:
  ///   - path: The object path inside the bucket.
  ///   - expiresIn: Seconds until the URL expires.
  ///   - download: When `true`, sets `Content-Disposition: attachment` on the response.
  ///   - transform: Optional image transformation parameters.
  ///   - cacheNonce: Optional nonce for CDN cache-busting.
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: Bool,
    transform: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) async throws -> URL {
    fatalError("not yet implemented")
  }

  /// Creates signed URLs for multiple paths in a single request.
  /// - Parameters:
  ///   - paths: An array of object paths to sign.
  ///   - expiresIn: Seconds until the URLs expire.
  ///   - download: An optional filename to trigger a browser download.
  ///   - cacheNonce: Optional nonce for CDN cache-busting.
  public func createSignedURLs(
    paths: [String], expiresIn: Int, download: String? = nil, cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    fatalError("not yet implemented")
  }

  /// Creates signed URLs for multiple paths in a single request.
  /// - Parameters:
  ///   - paths: An array of object paths to sign.
  ///   - expiresIn: Seconds until the URLs expire.
  ///   - download: When `true`, sets `Content-Disposition: attachment` on each response.
  ///   - cacheNonce: Optional nonce for CDN cache-busting.
  public func createSignedURLs(
    paths: [String], expiresIn: Int, download: Bool, cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    fatalError("not yet implemented")
  }

  // MARK: Delete

  /// Removes the objects at `paths` from the bucket.
  /// - Returns: Metadata for the deleted objects.
  @discardableResult
  public func remove(paths: [String]) async throws -> [FileObject] {
    fatalError("not yet implemented")
  }

  // MARK: List / Info

  /// Lists objects in the bucket, optionally filtered to a sub-path.
  /// - Parameters:
  ///   - path: Folder prefix to list. Pass `nil` to list the bucket root.
  ///   - options: Pagination and search options.
  public func list(path: String? = nil, options: SearchOptions? = nil) async throws -> [FileObject]
  {
    fatalError("not yet implemented")
  }

  /// Downloads an object at `path`.
  /// - Parameters:
  ///   - path: The object path inside the bucket.
  ///   - options: Optional image transformation parameters.
  ///   - additionalQueryItems: Extra URL query items appended to the request.
  ///   - cacheNonce: Optional nonce for CDN cache-busting.
  public func download(
    path: String,
    options: TransformOptions? = nil,
    query additionalQueryItems: [URLQueryItem]? = nil,
    cacheNonce: String? = nil
  ) async throws -> Data {
    fatalError("not yet implemented")
  }

  /// Returns metadata about the object at `path`.
  public func info(path: String) async throws -> FileObjectV2 {
    fatalError("not yet implemented")
  }

  /// Returns `true` if an object exists at `path`, `false` otherwise.
  public func exists(path: String) async throws -> Bool {
    fatalError("not yet implemented")
  }

  // MARK: Public URL

  /// Constructs the public URL for an object in a public bucket.
  /// - Parameters:
  ///   - path: The object path inside the bucket.
  ///   - download: An optional filename to trigger a browser download.
  ///   - options: Optional image transformation parameters.
  ///   - cacheNonce: Optional nonce for CDN cache-busting.
  public func getPublicURL(
    path: String,
    download: String? = nil,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    fatalError("not yet implemented")
  }

  /// Constructs the public URL for an object, optionally triggering a download.
  public func getPublicURL(
    path: String,
    download: Bool,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    fatalError("not yet implemented")
  }

  // MARK: Signed upload URL

  /// Creates a signed upload URL that a client can use to upload directly to Storage.
  /// - Parameters:
  ///   - path: The destination path for the upload.
  ///   - options: Options controlling upsert behaviour.
  public func createSignedUploadURL(
    path: String, options: CreateSignedUploadURLOptions? = nil
  ) async throws -> SignedUploadURL {
    fatalError("not yet implemented")
  }

  /// Uploads `data` to a pre-signed upload URL.
  /// - Parameters:
  ///   - path: The destination path matching the signed URL.
  ///   - token: The upload token from ``createSignedUploadURL(path:options:)``.
  ///   - data: The file contents to upload.
  ///   - options: Upload options such as content type.
  @discardableResult
  public func uploadToSignedURL(
    _ path: String, token: String, data: Data, options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    fatalError("not yet implemented")
  }

  /// Uploads the file at `fileURL` to a pre-signed upload URL.
  /// - Parameters:
  ///   - path: The destination path matching the signed URL.
  ///   - token: The upload token from ``createSignedUploadURL(path:options:)``.
  ///   - fileURL: A local URL pointing to the file to upload.
  ///   - options: Upload options such as content type.
  @discardableResult
  public func uploadToSignedURL(
    _ path: String, token: String, fileURL: URL, options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    fatalError("not yet implemented")
  }
}
