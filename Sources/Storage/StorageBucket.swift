public import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum FileUpload {
  case data(Data)
  case url(URL)

  /// The raw request body. A `Data` upload is sent from memory; a file URL streams from disk
  /// through `URLSession`'s upload task, so neither shape is copied by the SDK.
  func httpBody() throws -> HTTPBody {
    switch self {
    case .data(let data): HTTPBody(data)
    case .url(let url): try HTTPBody(fileURL: url)
    }
  }

  func contentType(forPath path: String, options: FileOptions) -> String {
    if let contentType = options.contentType { return contentType }
    switch self {
    case .data: return mimeType(forPathExtension: path.pathExtension)
    case .url(let url): return mimeType(forPathExtension: url.pathExtension)
    }
  }
}

/// A handle on one Storage bucket, for file operations within it.
///
/// Obtain a ``StorageBucket`` by calling ``StorageClient/from(_:)`` with the bucket
/// identifier you want to operate on:
///
/// ```swift
/// let avatars = storage.from("avatars")
///
/// // Upload a PNG
/// try await avatars.upload(path: "user123.png", data: imageData)
///
/// // Generate a signed URL valid for 60 seconds
/// let url = try await avatars.createSignedURL(path: "user123.png", expiresIn: 60)
/// ```
///
/// ## Topics
///
/// ### Uploading files
///
/// - ``upload(path:data:options:)``
/// - ``upload(path:fileURL:options:)``
/// - ``update(path:data:options:)``
/// - ``update(path:fileURL:options:)``
///
/// ### Uploading via signed URLs
///
/// - ``createSignedUploadURL(path:options:)``
/// - ``uploadToSignedURL(path:token:data:options:)``
/// - ``uploadToSignedURL(path:token:fileURL:options:)``
///
/// ### Downloading files
///
/// - ``download(path:options:query:cacheNonce:)``
/// - ``publicURL(path:download:options:cacheNonce:)-(_,DownloadBehavior?,_,_)``
///
/// ### Managing files
///
/// - ``move(from:to:options:)``
/// - ``copy(from:to:options:)``
/// - ``remove(paths:)``
/// - ``list(path:options:)``
/// - ``info(path:)``
/// - ``exists(path:)``
/// - ``purgeCache(path:transformationsOnly:)``
///
/// ### Creating signed URLs
///
/// - ``createSignedURL(path:expiresIn:download:transform:cacheNonce:)-(_,_,DownloadBehavior?,_,_)``
/// - ``createSignedURLs(paths:expiresIn:download:cacheNonce:)-(_,_,DownloadBehavior?,_)``
///
/// ### Customizing headers
///
/// - ``setHeader(_:forKey:)``
///
/// ### Configuration
///
/// - ``configuration``
public struct StorageBucket: Sendable {
  /// The identifier of the bucket this instance operates on.
  public let id: String

  let api: StorageAPI

  /// The configuration used to initialize this client instance.
  public var configuration: StorageClientConfiguration { api.configuration }

  init(id: String, api: StorageAPI) {
    self.id = id
    self.api = api
  }

  /// Returns a new ``StorageBucket`` with an additional HTTP header merged into the underlying
  /// configuration, included in all requests made by the returned instance.
  ///
  /// Because ``StorageBucket`` is an immutable value type, this method does not mutate `self` —
  /// it returns a new instance. Discarding the return value is a no-op, so always use the result:
  ///
  /// ```swift
  /// storage.from("avatars")
  ///   .setHeader("x-custom-header", forKey: "X-Custom-Header")
  ///   .list()
  /// ```
  ///
  /// - Parameters:
  ///   - value: The value of the header field.
  ///   - key: The name of the header field. The key is case-insensitively stored as lowercase.
  /// - Returns: A new ``StorageBucket`` with the header merged into the configuration's headers.
  public func setHeader(_ value: String, forKey key: String) -> Self {
    StorageBucket(id: id, api: api.setHeader(value, forKey: key))
  }

  private struct SignedURLAPIResponse: Decodable {
    let signedURL: String
  }

  private struct SignedURLsAPIResponse: Decodable {
    let signedURL: String?
    let path: String
    let error: String?
  }

  private func _uploadOrUpdate(
    method: HTTPRequest.Method,
    path: String,
    file: FileUpload,
    options: FileOptions
  ) async throws -> FileUploadResponse {
    let key = try ObjectKey(path)
    let response: UploadResponse = try await api.execute(
      api.requests.upload(method: method, bucket: id, key: key, file: file, options: options)
    )
    .decoded()

    guard let objectId = response.id else {
      throw StorageError(kind: .decoding, message: "The upload response carries no object id.")
    }

    return FileUploadResponse(id: objectId, path: key.path, fullPath: response.key)
  }

  /// Uploads a file to an existing bucket.
  ///
  /// ```swift
  /// let response = try await storage.from("avatars").upload(path: "user123.png", data: imageData)
  /// print(response.fullPath) // "avatars/user123.png"
  /// ```
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to upload.
  ///   - data: The raw bytes to store in the bucket.
  ///   - options: Upload options such as cache control, content type, and upsert behavior.
  /// - Returns: A ``FileUploadResponse`` containing the stored object's identifier and path.
  /// - Throws: ``StorageError`` if the upload fails or the caller is not authorized.
  @discardableResult
  public func upload(
    path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await _uploadOrUpdate(method: .post, path: path, file: .data(data), options: options)
  }

  /// Uploads a file from a local file URL to an existing bucket.
  ///
  /// Use this overload when you have a `URL` pointing to a file on disk rather than raw `Data`
  /// already loaded in memory. This is preferable for large files because the data is streamed
  /// rather than read entirely into memory first.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to upload.
  ///   - fileURL: A `file://` URL pointing to the local file to upload.
  ///   - options: Upload options such as cache control, content type, and upsert behavior.
  /// - Returns: A ``FileUploadResponse`` containing the stored object's identifier and path.
  /// - Throws: ``StorageError`` if the upload fails or the caller is not authorized.
  @discardableResult
  public func upload(
    path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await _uploadOrUpdate(method: .post, path: path, file: .url(fileURL), options: options)
  }

  /// Replaces an existing file at the specified path with new data.
  ///
  /// Unlike ``upload(path:data:options:)`` with `shouldUpsert: true`, this method always targets an
  /// existing object and will throw if the path does not exist.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to update.
  ///   - data: The raw bytes to overwrite the existing file with.
  ///   - options: Upload options such as cache control and content type.
  /// - Returns: A ``FileUploadResponse`` containing the updated object's identifier and path.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @discardableResult
  public func update(
    path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await _uploadOrUpdate(method: .put, path: path, file: .data(data), options: options)
  }

  /// Replaces an existing file at the specified path with a new local file.
  ///
  /// Use this overload when the replacement content is available as a `URL` pointing to a file on
  /// disk rather than raw `Data`. Large files are streamed rather than fully loaded into memory.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to update.
  ///   - fileURL: A `file://` URL pointing to the local file to use as the replacement.
  ///   - options: Upload options such as cache control and content type.
  /// - Returns: A ``FileUploadResponse`` containing the updated object's identifier and path.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @discardableResult
  public func update(
    path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await _uploadOrUpdate(method: .put, path: path, file: .url(fileURL), options: options)
  }

  /// Moves an existing file to a new path, optionally within a different bucket.
  ///
  /// ```swift
  /// try await storage.from("docs").move(from: "draft.pdf", to: "published/report.pdf")
  /// ```
  ///
  /// - Parameters:
  ///   - source: The original file path including the file name, e.g. `"folder/image.png"`.
  ///   - destination: The new file path including the new file name, e.g. `"archive/image.png"`.
  ///   - options: Optional ``DestinationOptions`` specifying a destination bucket. When `nil`,
  ///     the file is moved within the same bucket.
  /// - Throws: ``StorageError`` if the source does not exist or the caller is not authorized.
  public func move(
    from source: String,
    to destination: String,
    options: DestinationOptions? = nil
  ) async throws {
    try await api.execute(
      api.requests.move(
        bucket: id, source: ObjectKey(source), destination: ObjectKey(destination),
        destinationBucket: options?.destinationBucket)
    )
  }

  /// Copies an existing file to a new path, optionally within a different bucket.
  ///
  /// ```swift
  /// let newPath = try await storage.from("docs").copy(from: "original.pdf", to: "backup/original.pdf")
  /// ```
  ///
  /// - Parameters:
  ///   - source: The original file path including the file name, e.g. `"folder/image.png"`.
  ///   - destination: The destination path including the new file name, e.g. `"folder/image-copy.png"`.
  ///   - options: Optional ``DestinationOptions`` specifying a destination bucket. When `nil`,
  ///     the file is copied within the same bucket.
  /// - Returns: The full storage path of the newly created copy.
  /// - Throws: ``StorageError`` if the source does not exist or the caller is not authorized.
  @discardableResult
  public func copy(
    from source: String,
    to destination: String,
    options: DestinationOptions? = nil
  ) async throws -> String {
    try await api.execute(
      api.requests.copy(
        bucket: id, source: ObjectKey(source), destination: ObjectKey(destination),
        destinationBucket: options?.destinationBucket)
    )
    .decoded(as: UploadResponse.self)
    .key
  }

  /// Creates a signed URL for sharing a private file for a fixed period of time.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - expiresIn: Seconds until the URL expires, e.g. `60` for one minute.
  ///   - download: An optional custom download filename. Pass a non-nil string to force a download
  ///     with that filename in the `Content-Disposition` header, or `nil` for inline display.
  ///   - transform: Optional image transformation options applied server-side before delivery.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: A signed `URL` ready to share.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @_disfavoredOverload
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: String? = nil,
    transform: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) async throws -> URL {
    let response = try await api.execute(
      api.requests.sign(
        bucket: id, key: ObjectKey(path), expiresIn: expiresIn, transform: transform)
    )
    .decoded(as: SignedURLAPIResponse.self)

    return try api.requests.resolve(
      response.signedURL, query: Self.urlQuery(download: download, cacheNonce: cacheNonce))
  }

  /// Creates a signed URL for sharing a private file for a fixed period of time.
  ///
  /// ```swift
  /// // Inline preview URL, valid for 5 minutes
  /// let url = try await storage.from("docs").createSignedURL(path: "report.pdf", expiresIn: 300)
  ///
  /// // Force download with original file name
  /// let downloadURL = try await storage.from("docs").createSignedURL(
  ///   path: "report.pdf",
  ///   expiresIn: 60,
  ///   download: .withOriginalName
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - expiresIn: Seconds until the URL expires, e.g. `60` for one minute.
  ///   - download: Controls whether the URL triggers a file download. Pass `.withOriginalName` to
  ///     download using the file's original name, `.named("custom.pdf")` for a custom name, or
  ///     `nil` for inline display.
  ///   - transform: Optional image transformation options applied server-side before delivery.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: A signed `URL` ready to share.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: DownloadBehavior? = nil,
    transform: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) async throws -> URL {
    try await createSignedURL(
      path: path,
      expiresIn: expiresIn,
      download: download?.queryValue,
      transform: transform,
      cacheNonce: cacheNonce
    )
  }

  /// Creates signed URLs for multiple files in a single request.
  ///
  /// Each element in the returned array is a ``SignedURLResult``: either
  /// `.success(path:signedURL:)` or `.failure(path:error:)`. Exactly one case applies per item.
  /// Paths that do not exist produce a `.failure` result rather than throwing.
  ///
  /// - Parameters:
  ///   - paths: File paths to sign, e.g. `["folder/image.png", "folder2/image2.png"]`.
  ///   - expiresIn: Seconds until the URLs expire, e.g. `60` for one minute.
  ///   - download: An optional custom download filename. Pass a non-nil string to force a download,
  ///     or `nil` for inline display.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: An array of ``SignedURLResult`` values, one per requested path.
  /// - Throws: ``StorageError`` if the request itself fails (e.g. unauthorized). Individual missing
  ///   paths are reported as ``SignedURLResult/failure(path:error:)`` rather than thrown.
  @_disfavoredOverload
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: String? = nil,
    cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    let response = try await api.execute(
      api.requests.sign(bucket: id, keys: paths.map { try ObjectKey($0) }, expiresIn: expiresIn)
    )
    .decoded(as: [SignedURLsAPIResponse].self)

    let query = Self.urlQuery(download: download, cacheNonce: cacheNonce)
    return try response.map { item in
      if let signedURLString = item.signedURL {
        let url = try api.requests.resolve(signedURLString, query: query)
        return .success(path: item.path, signedURL: url)
      } else {
        return .failure(path: item.path, error: item.error ?? "Unknown error")
      }
    }
  }

  /// Creates signed URLs for multiple files in a single request.
  ///
  /// Each element in the returned array is a ``SignedURLResult``: either
  /// `.success(path:signedURL:)` or `.failure(path:error:)`. Exactly one case applies per item.
  /// Paths that do not exist produce a `.failure` result rather than throwing.
  ///
  /// ```swift
  /// let results = try await storage.from("docs").createSignedURLs(
  ///   paths: ["a.pdf", "b.pdf", "missing.pdf"],
  ///   expiresIn: 3600
  /// )
  /// for result in results {
  ///   switch result {
  ///   case .success(let path, let url): print(path, url)
  ///   case .failure(let path, let error): print(path, "failed:", error)
  ///   }
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - paths: File paths to sign, e.g. `["folder/image.png", "folder2/image2.png"]`.
  ///   - expiresIn: Seconds until the URLs expire, e.g. `60` for one minute.
  ///   - download: Controls whether the URLs trigger a file download. Pass `.withOriginalName` to
  ///     download using each file's original name, `.named("custom")` for a custom name, or `nil`
  ///     for inline display.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: An array of ``SignedURLResult`` values, one per requested path, preserving order.
  /// - Throws: ``StorageError`` if the request itself fails (e.g. unauthorized). Individual missing
  ///   paths are reported as ``SignedURLResult/failure(path:error:)`` rather than thrown.
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: DownloadBehavior? = nil,
    cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    try await createSignedURLs(
      paths: paths,
      expiresIn: expiresIn,
      download: download?.queryValue,
      cacheNonce: cacheNonce
    )
  }

  /// The `download` and `cacheNonce` query items every URL-returning method appends.
  private static func urlQuery(download: String?, cacheNonce: String?) -> [URLQueryItem] {
    var query: [URLQueryItem] = []
    if let download {
      query.append(URLQueryItem(name: "download", value: download))
    }
    if let cacheNonce {
      query.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
    }
    return query
  }

  /// Deletes one or more files from the bucket.
  ///
  /// ```swift
  /// let removed = try await storage.from("avatars").remove(paths: ["user123.png", "temp/draft.png"])
  /// ```
  ///
  /// - Parameter paths: File paths to delete, including the file name,
  ///   e.g. `["folder/image.png", "other/doc.pdf"]`.
  /// - Returns: An array of ``FileObject`` values representing the files that were removed.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  @discardableResult
  public func remove(paths: [String]) async throws -> [FileObject] {
    try await api.execute(api.requests.remove(bucket: id, keys: paths.map { try ObjectKey($0) }))
      .decoded()
  }

  /// Lists all files within a bucket folder.
  ///
  /// ```swift
  /// let files = try await storage.from("avatars").list(path: "users/")
  /// ```
  ///
  /// - Parameters:
  ///   - path: The folder prefix to list, e.g. `"users/"`. Pass `nil` to list the bucket root.
  ///   - options: Search options for filtering, sorting, and paginating results. Defaults to the
  ///     first 100 files sorted by name ascending.
  /// - Returns: An array of ``FileObject`` values representing the matching files and folders.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func list(
    path: String? = nil,
    options: SearchOptions? = nil
  ) async throws -> [FileObject] {
    try await api.execute(
      api.requests.list(bucket: id, prefix: ObjectKey(prefix: path ?? ""), options: options)
    )
    .decoded()
  }

  /// Downloads a file from a private bucket and returns its raw bytes.
  ///
  /// For public buckets, prefer requesting the URL returned by
  /// ``publicURL(path:download:options:cacheNonce:)-(_,DownloadBehavior?,_,_)`` directly.
  ///
  /// ```swift
  /// let data = try await storage.from("avatars").download(path: "user123.png")
  /// let image = UIImage(data: data)
  /// ```
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - options: Optional image transformation options applied server-side before delivery.
  ///   - additionalQueryItems: Extra URL query items appended to the request.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: The raw file data.
  /// - Throws: ``StorageError`` if the file does not exist or the caller is not authorized.
  @discardableResult
  public func download(
    path: String,
    options: TransformOptions? = nil,
    query additionalQueryItems: [URLQueryItem]? = nil,
    cacheNonce: String? = nil
  ) async throws -> Data {
    try await api.execute(
      api.requests.download(
        bucket: id, key: ObjectKey(path), transform: options?.queryItems ?? [],
        query: (additionalQueryItems ?? []) + Self.urlQuery(download: nil, cacheNonce: cacheNonce))
    )
  }

  /// Retrieves metadata about an existing file without downloading its content.
  ///
  /// - Parameter path: The file path including the file name, e.g. `"folder/image.png"`.
  /// - Returns: A ``FileObjectV2`` containing size, content type, ETag, and other metadata.
  /// - Throws: ``StorageError`` if the file does not exist or the caller is not authorized.
  public func info(path: String) async throws -> FileObjectV2 {
    try await api.execute(api.requests.info(bucket: id, key: ObjectKey(path))).decoded()
  }

  /// Checks whether a file exists in the bucket without downloading it.
  ///
  /// Reads the object's metadata, so the answer is `false` only when Storage reports that the
  /// key does not exist (``StorageError/Code/noSuchKey``, or a 404 in the body with no code).
  /// Every other failure throws, including a missing bucket (``StorageError/Code/noSuchBucket``)
  /// and an expired session (``StorageError/Code/invalidJWT``), which a `HEAD` request could not
  /// tell apart from a missing file.
  ///
  /// - Parameter path: The file path including the file name, e.g. `"folder/image.png"`.
  /// - Returns: `true` if the file exists and is accessible, `false` if it does not exist.
  /// - Throws: ``StorageError`` for errors other than a missing key (e.g. network failure,
  ///   authorization errors, or a missing bucket).
  public func exists(path: String) async throws -> Bool {
    do {
      _ = try await info(path: path)
      return true
    } catch let error as StorageError
      where error.code == .noSuchKey || (error.code == nil && error.serverStatusCode == 404)
    {
      return false
    }
  }

  /// Purges the CDN cache for a file, so the next request for it is served from Storage again.
  ///
  /// > Important: This requires the `secret` key. On self-hosted Storage, the `purgeCache` tenant
  /// > feature and a CDN purge endpoint must be configured, otherwise the request fails.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`. Only that exact
  ///     file is purged; there is no wildcard or folder purge.
  ///   - transformationsOnly: Pass `true` to purge only the resized and reformatted variants,
  ///     leaving the original file cached.
  /// - Throws: ``StorageError`` if the caller is not authorized or cache purging is not enabled.
  public func purgeCache(path: String, transformationsOnly: Bool = false) async throws {
    try await api.execute(
      api.requests.purgeCache(
        bucket: id, key: ObjectKey(path), transformationsOnly: transformationsOnly)
    )
  }

  /// Returns the public URL for a file in a public bucket.
  ///
  /// > Note: The bucket must be set to public for this URL to be accessible without authentication.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - download: An optional custom download filename. Pass a non-nil string to force a download
  ///     with that name, or `nil` for inline display.
  ///   - options: Optional image transformation options applied server-side before delivery.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: The publicly accessible `URL` for the file.
  /// - Throws: ``StorageError`` with kind ``StorageError/Kind-swift.struct/invalidRequest`` if the path is empty or contains a `..` segment.
  @_disfavoredOverload
  public func publicURL(
    path: String,
    download: String? = nil,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    api.requests.publicURL(
      bucket: id, key: try ObjectKey(path), transform: options?.queryItems ?? [],
      query: Self.urlQuery(download: download, cacheNonce: cacheNonce))
  }

  /// Returns the public URL for a file in a public bucket.
  ///
  /// ```swift
  /// // Inline display URL
  /// let url = try storage.from("avatars").publicURL(path: "user123.png")
  ///
  /// // Force download with original file name
  /// let dlURL = try storage.from("docs").publicURL(path: "report.pdf", download: .withOriginalName)
  /// ```
  ///
  /// > Note: The bucket must be set to public for this URL to be accessible without authentication.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - download: Controls whether the URL triggers a file download. Pass `.withOriginalName` to
  ///     download using the file's original name, `.named("custom.pdf")` for a custom name, or
  ///     `nil` for inline display.
  ///   - options: Optional image transformation options applied server-side before delivery.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: The publicly accessible `URL` for the file.
  /// - Throws: ``StorageError`` with kind ``StorageError/Kind-swift.struct/invalidRequest`` if the path is empty or contains a `..` segment.
  public func publicURL(
    path: String,
    download: DownloadBehavior? = nil,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    try publicURL(
      path: path,
      download: download?.queryValue,
      options: options,
      cacheNonce: cacheNonce
    )
  }

  /// Creates a signed upload URL that allows uploading a file without further authentication.
  ///
  /// Signed upload URLs are valid for 2 hours. Pass the returned ``SignedUploadURL/token`` to
  /// ``uploadToSignedURL(path:token:data:options:)`` (or the file-URL variant) to perform the upload.
  ///
  /// ```swift
  /// let signedUpload = try await storage.from("avatars").createSignedUploadURL(path: "user123.png")
  /// // Share signedUpload.token with the uploader
  /// try await storage.from("avatars").uploadToSignedURL(
  ///   path: "user123.png",
  ///   token: signedUpload.token,
  ///   data: imageData
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - path: The destination file path including the file name, e.g. `"folder/image.png"`.
  ///   - options: Optional ``CreateSignedUploadURLOptions`` controlling upsert behavior.
  /// - Returns: A ``SignedUploadURL`` containing the signed URL and an upload token.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func createSignedUploadURL(
    path: String,
    options: CreateSignedUploadURLOptions? = nil
  ) async throws -> SignedUploadURL {
    struct Response: Decodable {
      let url: String
    }

    let key = try ObjectKey(path)
    let response = try await api.execute(
      api.requests.createSignedUploadURL(
        bucket: id, key: key, upsert: options?.shouldUpsert ?? false)
    )
    .decoded(as: Response.self)

    let signedURL = try api.requests.resolve(response.url)
    guard
      let token = URLComponents(url: signedURL, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == "token" })?.value
    else {
      throw StorageError(kind: .decoding, message: "No token returned by API")
    }

    return SignedUploadURL(signedURL: signedURL, path: key.path, token: token)
  }

  /// Uploads raw data to a pre-signed upload URL.
  ///
  /// Obtain the `token` from ``createSignedUploadURL(path:options:)`` before calling this method.
  ///
  /// - Parameters:
  ///   - path: The destination file path, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist.
  ///   - token: The upload token from ``createSignedUploadURL(path:options:)``.
  ///   - data: The raw bytes to store in the bucket.
  ///   - options: Optional upload options such as cache control and content type.
  /// - Returns: A ``SignedURLUploadResponse`` containing the stored object path.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    data: Data,
    options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    try await _uploadToSignedURL(path: path, token: token, file: .data(data), options: options)
  }

  /// Uploads a local file to a pre-signed upload URL.
  ///
  /// Obtain the `token` from ``createSignedUploadURL(path:options:)`` before calling this method.
  /// Use this overload for large files where streaming from disk is preferable to loading all
  /// content into memory.
  ///
  /// - Parameters:
  ///   - path: The destination file path, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist.
  ///   - token: The upload token from ``createSignedUploadURL(path:options:)``.
  ///   - fileURL: A `file://` URL pointing to the local file to upload.
  ///   - options: Optional upload options such as cache control and content type.
  /// - Returns: A ``SignedURLUploadResponse`` containing the stored object path.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    fileURL: URL,
    options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    try await _uploadToSignedURL(path: path, token: token, file: .url(fileURL), options: options)
  }

  private func _uploadToSignedURL(
    path: String,
    token: String,
    file: FileUpload,
    options: FileOptions?
  ) async throws -> SignedURLUploadResponse {
    let key = try ObjectKey(path)
    let response: UploadResponse = try await api.execute(
      api.requests.uploadToSignedURL(
        bucket: id, key: key, token: token, file: file, options: options ?? FileOptions())
    )
    .decoded()

    return SignedURLUploadResponse(path: key.path, fullPath: response.key)
  }
}
