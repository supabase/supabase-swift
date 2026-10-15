import ConcurrencyExtras
public import Foundation
public import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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
/// let url = try await avatars.createSignedURL(path: "user123.png", expiresIn: .seconds(60))
/// ```
///
/// ## Topics
///
/// ### Uploading files
///
/// - ``upload(path:data:options:progress:)``
/// - ``upload(path:fileURL:options:progress:)``
/// - ``upload(path:body:options:progress:)``
/// - ``update(path:data:options:progress:)``
/// - ``update(path:fileURL:options:progress:)``
/// - ``update(path:body:options:progress:)``
///
/// ### Uploading via signed URLs
///
/// - ``createSignedUploadURL(path:upsert:)``
/// - ``uploadToSignedURL(path:token:data:options:progress:)``
/// - ``uploadToSignedURL(path:token:fileURL:options:progress:)``
/// - ``uploadToSignedURL(path:token:body:options:progress:)``
///
/// ### Downloading files
///
/// - ``download(path:transform:options:progress:)``
/// - ``DownloadResponse``
/// - ``publicURL(path:download:transform:versionId:cacheNonce:)``
///
/// ### Managing files
///
/// - ``move(from:to:toBucket:sourceVersionId:)``
/// - ``copy(from:to:toBucket:sourceVersionId:)``
/// - ``remove(paths:)``
/// - ``remove(versions:)``
/// - ``objects(prefix:options:)``
/// - ``list(path:options:)``
/// - ``info(path:versionId:)``
/// - ``exists(path:)``
/// - ``purgeCache(path:transformationsOnly:)``
///
/// ### Creating signed URLs
///
/// - ``createSignedURL(path:expiresIn:download:transform:versionId:cacheNonce:)``
/// - ``createSignedURLs(paths:expiresIn:download:cacheNonce:)``
///
/// ### Customizing headers
///
/// - ``setHeader(name:value:)``
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
  ///   .setHeader(name: .init("X-Custom-Header")!, value: "x-custom-header")
  ///   .list()
  /// ```
  ///
  /// - Parameters:
  ///   - name: The header field. Names match case-insensitively.
  ///   - value: The value of the header field.
  /// - Returns: A new ``StorageBucket`` with the header merged into the configuration's headers.
  public func setHeader(name: HTTPField.Name, value: String) -> Self {
    StorageBucket(id: id, api: api.setHeader(name: name, value: value))
  }

  private struct SignedURLAPIResponse: Decodable {
    let signedURL: String
  }

  private struct SignedURLsAPIResponse: Decodable {
    let signedURL: String?
    let path: String
    let error: String?
  }

  /// Sends an upload request, reporting the request body's progress to `progress`.
  private func sendUpload(
    _ request: StorageRequest,
    progress: (@Sendable (TransferProgress) -> Void)?
  ) async throws -> UploadResponse {
    var request = request
    guard let progress, let body = request.body else {
      return try await api.execute(request).decoded()
    }
    request.body = body.reportingProgress { [length = body.length] in
      progress(TransferProgress(completedBytes: $0, of: length))
    }
    return try await api.execute(request).decoded()
  }

  private func _uploadOrUpdate(
    method: HTTPRequest.Method,
    path: String,
    body: HTTPBody,
    options: UploadOptions,
    progress: (@Sendable (TransferProgress) -> Void)?
  ) async throws -> UploadedObject {
    let key = try ObjectKey(path)
    let response = try await sendUpload(
      api.requests.upload(method: method, bucket: id, key: key, body: body, options: options),
      progress: progress)

    return UploadedObject(
      id: response.id.flatMap(UUID.init(uuidString:)), path: key.path, fullPath: response.key)
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
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` containing the stored object's identifier and path.
  /// - Throws: ``StorageError`` if the upload fails or the caller is not authorized.
  @discardableResult
  public func upload(
    path: String,
    data: Data,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadOrUpdate(
      method: .post, path: path, body: HTTPBody(data), options: options, progress: progress)
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
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` containing the stored object's identifier and path.
  /// - Throws: ``StorageError`` if the upload fails or the caller is not authorized.
  @discardableResult
  public func upload(
    path: String,
    fileURL: URL,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadOrUpdate(
      method: .post, path: path, body: HTTPBody(fileURL: fileURL),
      options: options.inferringContentType(from: fileURL), progress: progress)
  }

  /// Uploads a stream of bytes to an existing bucket.
  ///
  /// The body streams as it is sent, so its bytes never have to sit in memory at once. A
  /// ``HTTPBody/Length/known(_:)`` length is sent as `Content-Length`, which lets Storage refuse
  /// an object over the bucket's size limit before any byte is sent; with
  /// ``HTTPBody/Length/unknown`` the upload is sent chunked and only fails once the limit is
  /// passed. A ``HTTPBody/IterationBehavior/single`` body cannot be sent twice, so the request is
  /// never retried and a redirect is not followed.
  ///
  /// ```swift
  /// let body = HTTPBody(chunks, length: .known(size), iterationBehavior: .single)
  /// try await storage.from("videos").upload(path: "clip.mov", body: body)
  /// ```
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to upload.
  ///   - body: The bytes to store in the bucket.
  ///   - options: Upload options such as cache control, content type, and upsert behavior.
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` containing the stored object's identifier and path.
  /// - Throws: ``StorageError`` if the upload fails or the caller is not authorized.
  @discardableResult
  public func upload(
    path: String,
    body: HTTPBody,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadOrUpdate(
      method: .post, path: path, body: body, options: options, progress: progress)
  }

  /// Replaces an existing file at the specified path with new data.
  ///
  /// Unlike ``upload(path:data:options:progress:)`` with `upsert: true`, this method always targets an
  /// existing object and will throw if the path does not exist.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to update.
  ///   - data: The raw bytes to overwrite the existing file with.
  ///   - options: Upload options such as cache control and content type. `upsert` is ignored:
  ///     `update` always replaces the object.
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` containing the updated object's identifier and path.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @discardableResult
  public func update(
    path: String,
    data: Data,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadOrUpdate(
      method: .put, path: path, body: HTTPBody(data), options: options, progress: progress)
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
  ///   - options: Upload options such as cache control and content type. `upsert` is ignored:
  ///     `update` always replaces the object.
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` containing the updated object's identifier and path.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @discardableResult
  public func update(
    path: String,
    fileURL: URL,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadOrUpdate(
      method: .put, path: path, body: HTTPBody(fileURL: fileURL),
      options: options.inferringContentType(from: fileURL), progress: progress)
  }

  /// Replaces an existing file at the specified path with a stream of bytes.
  ///
  /// The body streams as it is sent, so its bytes never have to sit in memory at once. A
  /// ``HTTPBody/Length/known(_:)`` length is sent as `Content-Length`, which lets Storage refuse
  /// an object over the bucket's size limit before any byte is sent; with
  /// ``HTTPBody/Length/unknown`` the upload is sent chunked and only fails once the limit is
  /// passed. A ``HTTPBody/IterationBehavior/single`` body cannot be sent twice, so the request is
  /// never retried and a redirect is not followed.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to update.
  ///   - body: The bytes to overwrite the existing file with.
  ///   - options: Upload options such as cache control and content type. `upsert` is ignored:
  ///     `update` always replaces the object.
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` containing the updated object's identifier and path.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @discardableResult
  public func update(
    path: String,
    body: HTTPBody,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadOrUpdate(
      method: .put, path: path, body: body, options: options, progress: progress)
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
  ///   - toBucket: The bucket to move the file into. `nil` moves it within this bucket.
  ///   - sourceVersionId: The version of the source to move. `nil` moves the current version.
  /// - Throws: ``StorageError`` if the source does not exist or the caller is not authorized.
  public func move(
    from source: String,
    to destination: String,
    toBucket: String? = nil,
    sourceVersionId: String? = nil
  ) async throws {
    try await api.execute(
      api.requests.move(
        bucket: id, source: ObjectKey(source), destination: ObjectKey(destination),
        destinationBucket: toBucket, sourceVersionId: sourceVersionId)
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
  ///   - toBucket: The bucket to copy the file into. `nil` copies it within this bucket.
  ///   - sourceVersionId: The version of the source to copy. `nil` copies the current version.
  /// - Returns: The full storage path of the newly created copy.
  /// - Throws: ``StorageError`` if the source does not exist or the caller is not authorized.
  @discardableResult
  public func copy(
    from source: String,
    to destination: String,
    toBucket: String? = nil,
    sourceVersionId: String? = nil
  ) async throws -> String {
    try await api.execute(
      api.requests.copy(
        bucket: id, source: ObjectKey(source), destination: ObjectKey(destination),
        destinationBucket: toBucket, sourceVersionId: sourceVersionId)
    )
    .decoded(as: UploadResponse.self)
    .key
  }

  /// Creates a signed URL for sharing a private file for a fixed period of time.
  ///
  /// ```swift
  /// // Inline preview URL, valid for 5 minutes
  /// let url = try await storage.from("docs").createSignedURL(path: "report.pdf", expiresIn: .seconds(300))
  ///
  /// // Force download with original file name
  /// let downloadURL = try await storage.from("docs").createSignedURL(
  ///   path: "report.pdf",
  ///   expiresIn: .seconds(60),
  ///   download: .withOriginalName
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - expiresIn: How long the URL stays valid, e.g. `.seconds(60)`. Whole seconds are sent;
  ///     less than one second throws ``StorageError`` with kind `invalidRequest`.
  ///   - download: Controls whether the URL triggers a file download. Pass `.withOriginalName` to
  ///     download using the file's original name, `.named("custom.pdf")` for a custom name, or
  ///     `nil` for inline display.
  ///   - transform: An optional image transformation applied server-side before delivery.
  ///   - versionId: The version the URL serves. `nil` serves the current version.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: A signed `URL` ready to share.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  public func createSignedURL(
    path: String,
    expiresIn: Duration,
    download: DownloadBehavior? = nil,
    transform: ImageTransform? = nil,
    versionId: String? = nil,
    cacheNonce: String? = nil
  ) async throws -> URL {
    let response = try await api.execute(
      api.requests.sign(
        bucket: id, key: ObjectKey(path), expiresIn: Self.seconds(expiresIn),
        transform: transform, versionId: versionId)
    )
    .decoded(as: SignedURLAPIResponse.self)

    return try api.requests.resolve(
      response.signedURL, query: Self.urlQuery(download: download, cacheNonce: cacheNonce))
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
  ///   expiresIn: .seconds(3600)
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
  ///   - expiresIn: How long the URLs stay valid, e.g. `.seconds(60)`. Whole seconds are sent;
  ///     less than one second throws ``StorageError`` with kind `invalidRequest`.
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
    expiresIn: Duration,
    download: DownloadBehavior? = nil,
    cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    let response = try await api.execute(
      api.requests.sign(
        bucket: id, keys: paths.map { try ObjectKey($0) }, expiresIn: Self.seconds(expiresIn))
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

  /// The whole seconds the sign routes take. A per-call value, so a bad one throws rather than
  /// traps.
  private static func seconds(_ expiresIn: Duration) throws -> Int {
    guard expiresIn >= .seconds(1) else {
      throw StorageError(
        kind: .invalidRequest, message: "A signed URL must expire at least one second from now.")
    }
    return Int(expiresIn.components.seconds)
  }

  /// The `download` and `cacheNonce` query items every URL-returning method appends.
  private static func urlQuery(download: DownloadBehavior?, cacheNonce: String?) -> [URLQueryItem] {
    var query: [URLQueryItem] = []
    if let download {
      query.append(URLQueryItem(name: "download", value: download.queryValue))
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
  /// - Returns: An array of ``StorageObject`` values representing the files that were removed.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  @discardableResult
  public func remove(paths: [String]) async throws -> [StorageObject] {
    try await api.execute(api.requests.remove(bucket: id, keys: paths.map { try ObjectKey($0) }))
      .decoded()
  }

  /// Deletes specific versions of objects in a versioned bucket.
  ///
  /// ```swift
  /// let versions = try await bucket.list(path: "docs", options: ListOptions(versions: .only))
  /// try await bucket.remove(
  ///   versions: versions.compactMap { object in
  ///     object.version.map { ObjectVersion(path: "docs/\(object.name)", versionId: $0) }
  ///   })
  /// ```
  ///
  /// - Parameter versions: The object versions to delete.
  /// - Returns: The deleted versions.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  @discardableResult
  public func remove(versions: [ObjectVersion]) async throws -> [StorageObject] {
    try await api.execute(
      api.requests.remove(
        bucket: id, versions: versions.map { (try ObjectKey($0.path), $0.versionId) })
    )
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
  ///   - options: Paging, sort and filters. Defaults to the first 100 entries sorted by name
  ///     ascending.
  /// - Returns: The files and folders one level under `path`, with names relative to it. A
  ///   folder is an entry whose ``StorageObject/isFolder`` is `true`.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func list(
    path: String? = nil,
    options: ListOptions = ListOptions()
  ) async throws -> [StorageObject] {
    try await api.execute(
      api.requests.list(bucket: id, prefix: ObjectKey(prefix: path ?? ""), options: options)
    )
    .decoded()
  }

  /// Downloads a file, returning as soon as Storage sends the response headers.
  ///
  /// The response's ``DownloadResponse/body`` streams the object and can be read once. Read it
  /// into memory, write it to a file, or process it chunk by chunk:
  ///
  /// ```swift
  /// let avatars = storage.from("avatars")
  ///
  /// // Into memory
  /// let data = try await avatars.download(path: "user123.png").data()
  ///
  /// // To a file, without holding the object in memory
  /// try await avatars.download(path: "user123.png").write(to: fileURL)
  ///
  /// // Chunk by chunk
  /// for try await chunk in try await avatars.download(path: "user123.png").body {
  ///   parser.feed(chunk)
  /// }
  /// ```
  ///
  /// For public buckets, prefer requesting the URL returned by
  /// ``publicURL(path:download:transform:versionId:cacheNonce:)`` directly.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - transform: An optional image transformation applied server-side before delivery.
  ///   - options: The byte range, version, cache nonce and extra headers.
  ///   - progress: Called as the body is read; see ``TransferProgress``.
  ///     ``TransferProgress/totalBytes`` is `nil` when Storage sends no `Content-Length`, as for a
  ///     transformed image.
  /// - Returns: The response headers and the body.
  /// - Throws: ``StorageError`` if the file does not exist or the caller is not authorized,
  ///   before any byte of the body is read. A network failure while the body streams throws
  ///   ``StorageError`` with kind `transport` from the body.
  public func download(
    path: String,
    transform: ImageTransform? = nil,
    options: DownloadOptions = DownloadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> DownloadResponse {
    let (head, body) = try await api.stream(
      api.requests.download(
        bucket: id, key: ObjectKey(path), transform: transform, options: options)
    )
    var response = body ?? HTTPBody(Data())
    if let progress {
      // Not `reportingProgress`: Linux buffers responses into in-memory bodies, which it leaves
      // to `URLSession`'s upload counts. The counter makes the body one-pass, as documented.
      let read = LockIsolated<Int64>(0)
      let length = response.length
      response = HTTPBody(
        response.map { chunk in
          let completed = read.withValue {
            $0 += Int64(chunk.count)
            return $0
          }
          progress(TransferProgress(completedBytes: completed, of: length))
          return chunk
        },
        length: length, iterationBehavior: .single)
    }
    return DownloadResponse(httpResponse: head, body: response)
  }

  /// Retrieves metadata about an existing file without downloading its content.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - versionId: The version to describe. `nil` describes the current version.
  /// - Returns: A ``ObjectInfo`` containing size, content type, ETag, and other metadata.
  /// - Throws: ``StorageError`` if the file does not exist or the caller is not authorized.
  public func info(path: String, versionId: String? = nil) async throws -> ObjectInfo {
    try await api.execute(api.requests.info(bucket: id, key: ObjectKey(path), versionId: versionId))
      .decoded()
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
  /// ```swift
  /// // Inline display URL
  /// let url = storage.from("avatars").publicURL(path: "user123.png")
  ///
  /// // Force download with original file name
  /// let dlURL = storage.from("docs").publicURL(path: "report.pdf", download: .withOriginalName)
  /// ```
  ///
  /// > Note: The bucket must be set to public for this URL to be accessible without authentication.
  ///
  /// Never throws: the base URL was validated when the client was created and every path is
  /// percent-encoded into a valid URL. Whether Storage accepts the key is Storage's call, as it
  /// is for every other method; a `.` or `..` segment is sent encoded rather than refused.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - download: Controls whether the URL triggers a file download. Pass `.withOriginalName` to
  ///     download using the file's original name, `.named("custom.pdf")` for a custom name, or
  ///     `nil` for inline display.
  ///   - transform: An optional image transformation applied server-side before delivery.
  ///   - versionId: The version the URL serves. `nil` serves the current version.
  ///   - cacheNonce: An optional nonce appended as a `cacheNonce` query parameter for
  ///     cache-busting purposes.
  /// - Returns: The publicly accessible `URL` for the file.
  public func publicURL(
    path: String,
    download: DownloadBehavior? = nil,
    transform: ImageTransform? = nil,
    versionId: String? = nil,
    cacheNonce: String? = nil
  ) -> URL {
    var query = Self.urlQuery(download: download, cacheNonce: cacheNonce)
    if let versionId {
      query.append(URLQueryItem(name: "versionId", value: versionId))
    }
    return api.requests.publicURL(
      bucket: id, key: ObjectKey(lenient: path), transform: transform?.queryItems ?? [],
      query: query)
  }

  /// Creates a signed upload URL that allows uploading a file without further authentication.
  ///
  /// Signed upload URLs are valid for 2 hours. Pass the returned ``SignedUploadURL/token`` to
  /// ``uploadToSignedURL(path:token:data:options:progress:)`` (or the file-URL variant) to perform the upload.
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
  ///   - upsert: Whether the upload made with the token may replace an existing object at
  ///     `path`. Defaults to `false`.
  /// - Returns: A ``SignedUploadURL`` containing the signed URL and an upload token.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func createSignedUploadURL(
    path: String,
    upsert: Bool = false
  ) async throws -> SignedUploadURL {
    struct Response: Decodable {
      let url: String
    }

    let key = try ObjectKey(path)
    let response = try await api.execute(
      api.requests.createSignedUploadURL(bucket: id, key: key, upsert: upsert)
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
  /// Obtain the `token` from ``createSignedUploadURL(path:upsert:)`` before calling this method.
  ///
  /// - Parameters:
  ///   - path: The destination file path, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist.
  ///   - token: The upload token from ``createSignedUploadURL(path:upsert:)``.
  ///   - data: The raw bytes to store in the bucket.
  ///   - options: Upload options such as cache control and content type. `upsert` is ignored:
  ///     the token decides whether an existing object is replaced.
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` with the stored path; Storage returns no object id for a
  ///   signed-URL upload, so ``UploadedObject/id`` is `nil`.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    data: Data,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadToSignedURL(
      path: path, token: token, body: HTTPBody(data), options: options, progress: progress)
  }

  /// Uploads a local file to a pre-signed upload URL.
  ///
  /// Obtain the `token` from ``createSignedUploadURL(path:upsert:)`` before calling this method.
  /// Use this overload for large files where streaming from disk is preferable to loading all
  /// content into memory.
  ///
  /// - Parameters:
  ///   - path: The destination file path, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist.
  ///   - token: The upload token from ``createSignedUploadURL(path:upsert:)``.
  ///   - fileURL: A `file://` URL pointing to the local file to upload.
  ///   - options: Upload options such as cache control and content type. `upsert` is ignored:
  ///     the token decides whether an existing object is replaced.
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` with the stored path; Storage returns no object id for a
  ///   signed-URL upload, so ``UploadedObject/id`` is `nil`.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    fileURL: URL,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadToSignedURL(
      path: path, token: token, body: HTTPBody(fileURL: fileURL),
      options: options.inferringContentType(from: fileURL), progress: progress)
  }

  /// Uploads a stream of bytes to a pre-signed upload URL.
  ///
  /// Obtain the `token` from ``createSignedUploadURL(path:upsert:)`` before calling this method.
  /// The body streams as it is sent, so its bytes never have to sit in memory at once. A
  /// ``HTTPBody/Length/known(_:)`` length is sent as `Content-Length`, which lets Storage refuse
  /// an object over the bucket's size limit before any byte is sent; with
  /// ``HTTPBody/Length/unknown`` the upload is sent chunked and only fails once the limit is
  /// passed. A ``HTTPBody/IterationBehavior/single`` body cannot be sent twice, so the request is
  /// never retried and a redirect is not followed.
  ///
  /// - Parameters:
  ///   - path: The destination file path, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist.
  ///   - token: The upload token from ``createSignedUploadURL(path:upsert:)``.
  ///   - body: The bytes to store in the bucket.
  ///   - options: Upload options such as cache control and content type. `upsert` is ignored:
  ///     the token decides whether an existing object is replaced.
  ///   - progress: Called as the bytes are sent; see ``TransferProgress``.
  /// - Returns: An ``UploadedObject`` with the stored path; Storage returns no object id for a
  ///   signed-URL upload, so ``UploadedObject/id`` is `nil`.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    body: HTTPBody,
    options: UploadOptions = UploadOptions(),
    progress: (@Sendable (TransferProgress) -> Void)? = nil
  ) async throws -> UploadedObject {
    try await _uploadToSignedURL(
      path: path, token: token, body: body, options: options, progress: progress)
  }

  private func _uploadToSignedURL(
    path: String,
    token: String,
    body: HTTPBody,
    options: UploadOptions,
    progress: (@Sendable (TransferProgress) -> Void)?
  ) async throws -> UploadedObject {
    let key = try ObjectKey(path)
    let response = try await sendUpload(
      api.requests.uploadToSignedURL(
        bucket: id, key: key, token: token, body: body, options: options),
      progress: progress)

    return UploadedObject(id: nil, path: key.path, fullPath: response.key)
  }
}

extension UploadOptions {
  /// A file keeps its own type when the storage path has a different extension, or none.
  fileprivate func inferringContentType(from fileURL: URL) -> UploadOptions {
    var options = self
    options.contentType = contentType ?? mimeType(forPathExtension: fileURL.pathExtension)
    return options
  }
}
