import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let defaultSearchOptions = SearchOptions(
  limit: 100,
  offset: 0,
  sortBy: SortBy(
    column: "name",
    order: .ascending
  )
)

let defaultFileOptions = FileOptions(
  cacheControl: "3600",
  contentType: "text/plain;charset=UTF-8",
  upsert: false
)

enum FileUpload {
  case data(Data)
  case url(URL)

  func append(
    to builder: MultipartBuilder,
    withPath path: String,
    options: FileOptions
  ) -> MultipartBuilder {
    var builder = builder.addText(name: "cacheControl", value: options.cacheControl)

    if let metadata = options.metadata {
      builder = builder.addText(
        name: "metadata",
        value: String(data: encodeMetadata(metadata), encoding: .utf8) ?? ""
      )
    }

    switch self {
    case .data(let data):
      return builder.addData(
        name: "",
        data: data,
        fileName: path.fileName,
        mimeType: options.contentType
          ?? mimeType(forPathExtension: path.pathExtension)
      )

    case .url(let url):
      return builder.addFile(
        name: "",
        fileURL: url,
        fileName: url.lastPathComponent,
        mimeType: options.contentType
          ?? mimeType(forPathExtension: url.pathExtension)
      )
    }
  }

  var usesTempFileUpload: Bool {
    get throws {
      guard case .url(let url) = self else { return false }

      let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      return fileSize >= 10 * 1024 * 1024
    }
  }

  func defaultOptions() -> FileOptions {
    switch self {
    case .data:
      return defaultFileOptions

    case .url:
      var options = defaultFileOptions
      options.contentType = nil
      return options
    }
  }
}

#if DEBUG
  import ConcurrencyExtras
  let testingBoundary = LockIsolated<String?>(nil)
#endif

/// File operations API for objects stored within a single Supabase Storage bucket.
///
/// Obtain an instance by calling ``StorageClient/from(_:)`` — do not create one directly.
///
/// `StorageFileAPI` covers the full lifecycle of objects in a bucket: uploading, updating,
/// downloading, listing, deleting, moving, copying, and generating signed or public URLs.
///
/// ## Basic usage
///
/// ```swift
/// let bucket = supabase.storage.from("avatars")
///
/// // Upload
/// let response = try await bucket.upload("user-123/photo.png", data: imageData)
///
/// // Download
/// let data = try await bucket.download(path: "user-123/photo.png")
///
/// // Public URL (public bucket)
/// let url = try bucket.getPublicURL(path: "user-123/photo.png")
///
/// // Signed URL (private bucket, valid for 60 seconds)
/// let signedURL = try await bucket.createSignedURL(path: "user-123/photo.png", expiresIn: 60)
/// ```
///
/// - Note: All stored properties are immutable, making `StorageFileAPI` safe to share across
///   concurrency boundaries.
public struct StorageFileAPI: Sendable {
  /// The bucket id to operate on.
  let bucketId: String
  let client: StorageClient

  init(bucketId: String, client: StorageClient) {
    self.bucketId = bucketId
    self.client = client
  }

  private struct MoveResponse: Decodable {
    let message: String
  }

  private struct SignedURLAPIResponse: Decodable {
    let signedURL: String
  }

  private struct SignedURLsAPIResponse: Decodable {
    let signedURL: String?
    let path: String
    let error: String?
  }

  private enum Header {
    static let cacheControl = "Cache-Control"
    static let contentType = "Content-Type"
    static let duplex = "duplex"
    static let xUpsert = "x-upsert"
  }

  private struct UploadResponse: Decodable {
    let Key: String
    let Id: String
  }

  private struct SignedUploadResponse: Decodable {
    let Key: String
  }

  private func _uploadOrUpdate(
    method: HTTPMethod,
    path: String,
    file: FileUpload,
    options: FileOptions?
  ) async throws -> FileUploadResponse {
    let options = options ?? defaultFileOptions
    let cleanPath = _removeEmptyFolders(path)
    let _path = _getFinalPath(cleanPath)

    var headers = multipartHeaders(options: options)
    if method == .post {
      headers[Header.xUpsert] = "\(options.upsert)"
    }

    let response: UploadResponse = try await uploadMultipart(
      method,
      url: client.url.appendingPathComponent("object/\(_path)"),
      path: path,
      file: file,
      options: options,
      headers: headers
    )

    return FileUploadResponse(
      id: response.Id,
      path: path,
      fullPath: response.Key
    )
  }

  /// Uploads a `Data` value to an existing bucket.
  ///
  /// If the path already exists and ``FileOptions/upsert`` is `false` (the default), an error
  /// is returned. Set `upsert: true` to overwrite silently instead.
  ///
  /// - Parameters:
  ///   - path: The destination path within the bucket, e.g. `"folder/image.png"`.
  ///     The bucket must already exist.
  ///   - data: The raw file bytes to store.
  ///   - options: Upload options such as content type, cache duration, and upsert behaviour.
  /// - Returns: A ``FileUploadResponse`` containing the assigned storage ID and full path.
  /// - Throws: ``StorageError`` if the path already exists (when `upsert` is `false`), the
  ///   bucket does not exist, or the request otherwise fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let imageData = UIImage(named: "photo")!.jpegData(compressionQuality: 0.8)!
  /// let response = try await storage.from("avatars").upload(
  ///   "user-123/photo.jpg",
  ///   data: imageData,
  ///   options: FileOptions(contentType: "image/jpeg", upsert: true)
  /// )
  /// print(response.fullPath) // "avatars/user-123/photo.jpg"
  /// ```
  @discardableResult
  public func upload(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await _uploadOrUpdate(
      method: .post,
      path: path,
      file: .data(data),
      options: options
    )
  }

  /// Uploads a file from a local `URL` to an existing bucket.
  ///
  /// For files ≥ 10 MB the SDK automatically streams from a temporary file on disk to avoid
  /// loading the entire payload into memory.
  ///
  /// - Parameters:
  ///   - path: The destination path within the bucket, e.g. `"folder/image.png"`.
  ///     The bucket must already exist.
  ///   - fileURL: A local `file://` URL pointing to the file to upload.
  ///   - options: Upload options such as content type, cache duration, and upsert behaviour.
  ///     When `contentType` is `nil`, the MIME type is inferred from the file extension.
  /// - Returns: A ``FileUploadResponse`` containing the assigned storage ID and full path.
  /// - Throws: ``StorageError`` if the path already exists (when `upsert` is `false`), the
  ///   bucket does not exist, or the request otherwise fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
  /// let response = try await storage.from("documents").upload(
  ///   "reports/2024/annual.pdf",
  ///   fileURL: fileURL
  /// )
  /// ```
  @discardableResult
  public func upload(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await _uploadOrUpdate(
      method: .post,
      path: path,
      file: .url(fileURL),
      options: options
    )
  }

  /// Replaces an existing file at the specified path with new `Data`.
  ///
  /// Unlike ``upload(_:data:options:)``, this method always overwrites the existing object and
  /// returns an error if no object exists at the given path.
  ///
  /// - Parameters:
  ///   - path: The path of the file to replace, e.g. `"folder/image.png"`.
  ///     The bucket must already exist.
  ///   - data: The new raw file bytes.
  ///   - options: Upload options such as content type and cache duration.
  /// - Returns: A ``FileUploadResponse`` containing the storage ID and full path of the updated object.
  /// - Throws: ``StorageError`` if the path does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let newImageData = UIImage(named: "updated-photo")!.pngData()!
  /// let response = try await storage.from("avatars").update(
  ///   "user-123/photo.png",
  ///   data: newImageData,
  ///   options: FileOptions(contentType: "image/png")
  /// )
  /// ```
  @discardableResult
  public func update(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await _uploadOrUpdate(
      method: .put,
      path: path,
      file: .data(data),
      options: options
    )
  }

  /// Replaces an existing file at the specified path with the contents of a local `URL`.
  ///
  /// Unlike ``upload(_:fileURL:options:)``, this method always overwrites the existing object and
  /// returns an error if no object exists at the given path.
  ///
  /// - Parameters:
  ///   - path: The path of the file to replace, e.g. `"folder/image.png"`.
  ///     The bucket must already exist.
  ///   - fileURL: A local `file://` URL pointing to the replacement file.
  ///   - options: Upload options such as content type and cache duration.
  ///     When `contentType` is `nil`, the MIME type is inferred from the file extension.
  /// - Returns: A ``FileUploadResponse`` containing the storage ID and full path of the updated object.
  /// - Throws: ``StorageError`` if the path does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let newFileURL = URL(fileURLWithPath: "/tmp/updated-report.pdf")
  /// try await storage.from("documents").update("reports/2024/annual.pdf", fileURL: newFileURL)
  /// ```
  @discardableResult
  public func update(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await _uploadOrUpdate(
      method: .put,
      path: path,
      file: .url(fileURL),
      options: options
    )
  }

  /// Moves an existing file to a new path within the same or a different bucket.
  ///
  /// The source file is removed after the move completes. To keep the original, use ``copy(from:to:options:)`` instead.
  ///
  /// - Parameters:
  ///   - source: The current file path, e.g. `"folder/image.png"`.
  ///   - destination: The new file path, e.g. `"archive/image.png"`.
  ///   - options: Optional destination overrides, such as moving the file into a different bucket.
  /// - Throws: ``StorageError`` if the source path does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Rename within the same bucket
  /// try await storage.from("avatars").move(from: "old-name.png", to: "new-name.png")
  ///
  /// // Move to a different bucket
  /// try await storage.from("avatars").move(
  ///   from: "user-123/photo.png",
  ///   to: "user-123/photo.png",
  ///   options: DestinationOptions(destinationBucket: "archive")
  /// )
  /// ```
  public func move(
    from source: String,
    to destination: String,
    options: DestinationOptions? = nil
  ) async throws {
    let body: [String: String?] = [
      "bucketId": bucketId,
      "sourceKey": source,
      "destinationKey": destination,
      "destinationBucket": options?.destinationBucket,
    ]

    try await client.fetchData(
      .post,
      "object/move",
      body: .data(client.encoder.encode(body))
    )
  }

  /// Copies an existing file to a new path, leaving the original in place.
  ///
  /// To move a file without keeping the original, use ``move(from:to:options:)`` instead.
  ///
  /// - Parameters:
  ///   - source: The current file path, e.g. `"folder/image.png"`.
  ///   - destination: The path for the copy, e.g. `"folder/image-copy.png"`.
  ///   - options: Optional destination overrides, such as copying the file into a different bucket.
  /// - Returns: The full storage key of the newly created copy.
  /// - Throws: ``StorageError`` if the source path does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Duplicate a file in the same bucket
  /// let key = try await storage.from("avatars").copy(
  ///   from: "user-123/photo.png",
  ///   to: "user-123/photo-backup.png"
  /// )
  /// print(key) // "avatars/user-123/photo-backup.png"
  /// ```
  @discardableResult
  public func copy(
    from source: String,
    to destination: String,
    options: DestinationOptions? = nil
  ) async throws -> String {
    struct UploadResponse: Decodable {
      let Key: String
    }

    let body: [String: String?] = [
      "bucketId": bucketId,
      "sourceKey": source,
      "destinationKey": destination,
      "destinationBucket": options?.destinationBucket,
    ]

    let response: UploadResponse = try await client.fetchDecoded(
      .post,
      "object/copy",
      body: .data(client.encoder.encode(body))
    )

    return response.Key
  }

  /// Creates a signed URL that grants time-limited access to a private file.
  ///
  /// Signed URLs work for both private and public buckets. They are useful for sharing individual
  /// files with users who do not have Storage credentials.
  ///
  /// - Parameters:
  ///   - path: The file path within the bucket, e.g. `"folder/image.png"`.
  ///   - expiresIn: The number of seconds until the signed URL expires.
  ///     For example, `3600` for a URL valid for one hour.
  ///   - download: When non-`nil`, the browser treats the URL as a file download and uses this
  ///     string as the suggested file name. Pass an empty string (`""`) to use the original file name.
  ///   - transform: Optional on-the-fly image transformation applied before the file is served.
  ///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter. Use this to
  ///     invalidate cached signed URLs without changing the path.
  /// - Returns: A signed `URL` ready to be shared or embedded.
  /// - Throws: ``StorageError`` if the file does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // URL valid for 10 minutes
  /// let url = try await storage.from("private-docs").createSignedURL(
  ///   path: "user-123/contract.pdf",
  ///   expiresIn: 600,
  ///   download: "contract.pdf"
  /// )
  ///
  /// // Resized image URL valid for 1 hour
  /// let thumbnailURL = try await storage.from("photos").createSignedURL(
  ///   path: "gallery/hero.jpg",
  ///   expiresIn: 3600,
  ///   transform: TransformOptions(width: 300, height: 300, resize: .cover)
  /// )
  /// ```
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: String? = nil,
    transform: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) async throws -> URL {
    struct Body: Encodable {
      let expiresIn: Int
      let transform: TransformOptions?
    }

    let encoder = JSONEncoder.unconfiguredEncoder

    let response: SignedURLAPIResponse = try await client.fetchDecoded(
      .post,
      "object/sign/\(bucketId)/\(path)",
      body: .data(
        encoder.encode(
          Body(expiresIn: expiresIn, transform: transform)
        )
      )
    )

    return try makeSignedURL(
      response.signedURL,
      download: download,
      cacheNonce: cacheNonce
    )
  }

  /// Creates a signed URL that grants time-limited access to a private file, with a boolean
  /// download trigger.
  ///
  /// This overload is a convenience variant of
  /// ``createSignedURL(path:expiresIn:download:transform:cacheNonce:)`` that accepts a `Bool`
  /// instead of an optional file name string. When `download` is `true`, the browser uses the
  /// original file name for the download prompt.
  ///
  /// - Parameters:
  ///   - path: The file path within the bucket, e.g. `"folder/image.png"`.
  ///   - expiresIn: The number of seconds until the signed URL expires.
  ///   - download: Pass `true` to trigger a browser download using the original file name.
  ///   - transform: Optional on-the-fly image transformation applied before the file is served.
  ///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter for cache
  ///     invalidation.
  /// - Returns: A signed `URL` ready to be shared or embedded.
  /// - Throws: ``StorageError`` if the file does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let url = try await storage.from("docs").createSignedURL(
  ///   path: "report.pdf",
  ///   expiresIn: 300,
  ///   download: true
  /// )
  /// ```
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: Bool,
    transform: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) async throws -> URL {
    try await createSignedURL(
      path: path,
      expiresIn: expiresIn,
      download: download ? "" : nil,
      transform: transform,
      cacheNonce: cacheNonce
    )
  }

  /// Creates signed URLs for multiple files in a single request.
  ///
  /// All URLs share the same expiry window. The returned array has one ``SignedURLResult`` per
  /// input path, in the same order. Paths that cannot be signed (e.g. because the file does not
  /// exist) produce a ``SignedURLResult/failure(path:error:)`` entry rather than throwing.
  ///
  /// - Parameters:
  ///   - paths: The file paths within the bucket, e.g. `["folder/a.png", "folder/b.png"]`.
  ///   - expiresIn: The number of seconds until the signed URLs expire.
  ///   - download: When non-`nil`, the browser treats each URL as a file download and uses this
  ///     string as the suggested file name. Pass an empty string (`""`) to use each file's
  ///     original name.
  ///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter. Use this to
  ///     invalidate cached signed URLs without changing the paths.
  /// - Returns: An array of ``SignedURLResult`` values, one per input path.
  /// - Throws: ``StorageError`` if the batch request itself fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let results = try await storage.from("photos").createSignedURLs(
  ///   paths: ["gallery/a.jpg", "gallery/b.jpg", "missing.jpg"],
  ///   expiresIn: 3600
  /// )
  ///
  /// for result in results {
  ///   switch result {
  ///   case .success(let path, let url):
  ///     print("\(path) → \(url)")
  ///   case .failure(let path, let error):
  ///     print("\(path) failed: \(error)")
  ///   }
  /// }
  /// ```
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: String? = nil,
    cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    struct Params: Encodable {
      let expiresIn: Int
      let paths: [String]
    }

    let encoder = JSONEncoder.unconfiguredEncoder

    let response: [SignedURLsAPIResponse] = try await client.fetchDecoded(
      .post,
      "object/sign/\(bucketId)",
      body: .data(
        encoder.encode(
          Params(expiresIn: expiresIn, paths: paths)
        )
      )
    )

    return try response.map { item in
      if let signedURLString = item.signedURL {
        let url = try makeSignedURL(
          signedURLString,
          download: download,
          cacheNonce: cacheNonce
        )
        return .success(path: item.path, signedURL: url)
      } else {
        return .failure(path: item.path, error: item.error ?? "Unknown error")
      }
    }
  }

  /// Creates signed URLs for multiple files, with a boolean download trigger.
  ///
  /// This overload is a convenience variant of
  /// ``createSignedURLs(paths:expiresIn:download:cacheNonce:)`` that accepts a `Bool`
  /// instead of an optional file name string. When `download` is `true`, the browser uses each
  /// file's original name for the download prompt.
  ///
  /// - Parameters:
  ///   - paths: The file paths within the bucket, e.g. `["folder/a.png", "folder/b.png"]`.
  ///   - expiresIn: The number of seconds until the signed URLs expire.
  ///   - download: Pass `true` to trigger browser downloads using each file's original name.
  ///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter for cache
  ///     invalidation.
  /// - Returns: An array of ``SignedURLResult`` values, one per input path.
  /// - Throws: ``StorageError`` if the batch request itself fails.
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: Bool,
    cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    try await createSignedURLs(
      paths: paths,
      expiresIn: expiresIn,
      download: download ? "" : nil,
      cacheNonce: cacheNonce
    )
  }

  private func makeSignedURL(
    _ signedURL: String,
    download: String?,
    cacheNonce: String? = nil
  )
    throws -> URL
  {
    guard let signedURLComponents = URLComponents(string: signedURL),
      var baseComponents = URLComponents(
        url: client.url,
        resolvingAgainstBaseURL: false
      )
    else {
      throw URLError(.badURL)
    }

    baseComponents.path +=
      signedURLComponents.path.hasPrefix("/")
      ? signedURLComponents.path : "/\(signedURLComponents.path)"
    baseComponents.queryItems = signedURLComponents.queryItems

    if let download {
      baseComponents.queryItems = baseComponents.queryItems ?? []
      baseComponents.queryItems!.append(
        URLQueryItem(name: "download", value: download)
      )
    }

    if let cacheNonce {
      baseComponents.queryItems = baseComponents.queryItems ?? []
      baseComponents.queryItems!.append(
        URLQueryItem(name: "cacheNonce", value: cacheNonce)
      )
    }

    guard let signedURL = baseComponents.url else {
      throw URLError(.badURL)
    }

    return signedURL
  }

  /// Deletes one or more files from the bucket.
  ///
  /// All listed paths are deleted in a single request. Non-existent paths are silently ignored.
  ///
  /// - Parameter paths: The paths of the files to delete, e.g. `["folder/image.png", "other.pdf"]`.
  /// - Returns: An array of ``FileObject`` values describing the deleted files.
  /// - Throws: ``StorageError`` if the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let deleted = try await storage.from("avatars").remove(paths: [
  ///   "user-123/photo.png",
  ///   "user-456/photo.png"
  /// ])
  /// print("Deleted \(deleted.count) file(s)")
  /// ```
  @discardableResult
  public func remove(paths: [String]) async throws -> [FileObject] {
    try await client.fetchDecoded(
      .delete,
      "object/\(bucketId)",
      body: .data(client.encoder.encode(["prefixes": paths]))
    )
  }

  /// Lists files and folders within the bucket, optionally scoped to a path prefix.
  ///
  /// Results include both files and virtual folder entries. Paginate large buckets using
  /// ``SearchOptions/limit`` and ``SearchOptions/offset``.
  ///
  /// - Parameters:
  ///   - path: An optional folder path to list. When `nil`, lists the bucket root.
  ///   - options: Filtering, sorting, and pagination options. Defaults to 100 items sorted
  ///     by name ascending when `nil`.
  /// - Returns: An array of ``FileObject`` values representing the matching files and folders.
  /// - Throws: ``StorageError`` if the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // List all files in the "user-123" folder
  /// let files = try await storage.from("avatars").list(path: "user-123")
  ///
  /// // Paginate with custom sort
  /// let page2 = try await storage.from("photos").list(
  ///   path: "gallery",
  ///   options: SearchOptions(limit: 20, offset: 20, sortBy: SortBy(column: "created_at", order: .descending))
  /// )
  /// ```
  public func list(
    path: String? = nil,
    options: SearchOptions? = nil
  ) async throws -> [FileObject] {
    let encoder = JSONEncoder.unconfiguredEncoder

    var options = options ?? defaultSearchOptions
    options.prefix = path ?? ""

    return try await client.fetchDecoded(
      .post,
      "object/list/\(bucketId)",
      body: .data(encoder.encode(options))
    )
  }

  /// Downloads a file from the bucket and returns its raw bytes.
  ///
  /// Use this method for files in private buckets. For public buckets, construct a URL with
  /// ``getPublicURL(path:download:options:cacheNonce:)`` and fetch it directly instead —
  /// it avoids routing the bytes through the SDK.
  ///
  /// - Parameters:
  ///   - path: The path of the file to download, e.g. `"folder/image.png"`.
  ///   - options: Optional on-the-fly image transformation applied before the file is served.
  ///     When non-`nil` and non-empty, the request is routed through the image rendering pipeline.
  ///   - additionalQueryItems: Extra URL query parameters appended to the download request.
  ///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter for cache
  ///     invalidation.
  /// - Returns: The raw file data.
  /// - Throws: ``StorageError`` if the file does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Download raw file
  /// let data = try await storage.from("private-docs").download(path: "user-123/report.pdf")
  ///
  /// // Download with image transformation
  /// let thumbnail = try await storage.from("photos").download(
  ///   path: "gallery/hero.jpg",
  ///   options: TransformOptions(width: 100, height: 100, resize: .cover)
  /// )
  /// ```
  @discardableResult
  public func download(
    path: String,
    options: TransformOptions? = nil,
    query additionalQueryItems: [URLQueryItem]? = nil,
    cacheNonce: String? = nil
  ) async throws -> Data {
    var queryItems = options?.queryItems ?? []
    let renderPath =
      options.map { !$0.isEmpty } == true
      ? "render/image/authenticated" : "object"
    let _path = _getFinalPath(path)

    if let additionalQueryItems {
      queryItems.append(contentsOf: additionalQueryItems)
    }

    if let cacheNonce {
      queryItems.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
    }

    let (data, _) = try await client.fetchData(
      .get,
      url: storageURL(path: "\(renderPath)/\(_path)", queryItems: queryItems)
    )
    return data
  }

  /// Retrieves extended metadata for a file without downloading its contents.
  ///
  /// Returns a ``FileObjectV2`` that includes the file size, ETag, content type, and other
  /// server-side metadata. To check only whether a file exists, prefer ``exists(path:)``.
  ///
  /// - Parameter path: The path of the file within the bucket, e.g. `"folder/image.png"`.
  /// - Returns: A ``FileObjectV2`` containing the file's metadata.
  /// - Throws: ``StorageError`` if the file does not exist or the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let info = try await storage.from("avatars").info(path: "user-123/photo.png")
  /// print("Size: \(info.size ?? 0) bytes, type: \(info.contentType ?? "unknown")")
  /// ```
  public func info(path: String) async throws -> FileObjectV2 {
    let _path = _getFinalPath(path)

    return try await client.fetchDecoded(.get, "object/info/\(_path)")
  }

  /// Checks whether a file exists in the bucket.
  ///
  /// Issues a `HEAD` request and returns `true` if the server responds with a success status,
  /// `false` if the server returns 400 or 404. Any other error is re-thrown.
  ///
  /// - Parameter path: The path of the file within the bucket, e.g. `"folder/image.png"`.
  /// - Returns: `true` if the file exists, `false` if it does not.
  /// - Throws: ``StorageError`` for server errors other than 400/404.
  ///
  /// ## Example
  ///
  /// ```swift
  /// if try await storage.from("avatars").exists(path: "user-123/photo.png") {
  ///   print("File found")
  /// } else {
  ///   print("File not found")
  /// }
  /// ```
  public func exists(path: String) async throws -> Bool {
    do {
      try await client.fetchData(.head, "object/\(bucketId)/\(path)")
      return true
    } catch {
      var statusCode: Int?

      if let error = error as? StorageError {
        statusCode = error.statusCode.flatMap(Int.init)
      } else if let error = error as? HTTPError {
        statusCode = error.response.statusCode
      } else if case HTTPClientError.responseError(let response, _) = error {
        statusCode = response.statusCode
      }

      if let statusCode, [400, 404].contains(statusCode) {
        return false
      }

      throw error
    }
  }

  /// Returns the public URL for a file in a public bucket.
  ///
  /// The URL is constructed locally without a network request. This method does **not** verify
  /// that the bucket is actually public — requests to the returned URL will fail with a
  /// permission error if the bucket is private.
  ///
  /// > Note: Make the bucket public via ``StorageClient/updateBucket(_:options:)`` (set
  /// > `BucketOptions(public: true)`) or via the Supabase dashboard before using this method.
  ///
  /// - Parameters:
  ///   - path: The path of the file within the bucket, e.g. `"folder/image.png"`.
  ///   - download: When non-`nil`, the browser treats the URL as a file download and uses this
  ///     string as the suggested file name. Pass an empty string (`""`) to use the original name.
  ///   - options: Optional on-the-fly image transformation applied when the URL is fetched.
  ///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter for cache
  ///     invalidation.
  /// - Returns: The public `URL` for the file.
  /// - Throws: `URLError(.badURL)` if the resulting URL cannot be constructed.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Plain public URL
  /// let url = try storage.from("avatars").getPublicURL(path: "user-123/photo.png")
  ///
  /// // Resized thumbnail URL
  /// let thumbURL = try storage.from("avatars").getPublicURL(
  ///   path: "user-123/photo.png",
  ///   options: TransformOptions(width: 100, height: 100, resize: .cover)
  /// )
  ///
  /// // Force-download URL with a custom file name
  /// let downloadURL = try storage.from("documents").getPublicURL(
  ///   path: "report.pdf",
  ///   download: "annual-report-2024.pdf"
  /// )
  /// ```
  public func getPublicURL(
    path: String,
    download: String? = nil,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    var queryItems: [URLQueryItem] = []

    guard
      var components = URLComponents(
        url: client.url,
        resolvingAgainstBaseURL: true
      )
    else {
      throw URLError(.badURL)
    }

    if let download {
      queryItems.append(URLQueryItem(name: "download", value: download))
    }

    if let optionsQueryItems = options?.queryItems {
      queryItems.append(contentsOf: optionsQueryItems)
    }

    if let cacheNonce {
      queryItems.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
    }

    let renderPath =
      options.map { !$0.isEmpty } == true ? "render/image" : "object"

    components.path += "/\(renderPath)/public/\(bucketId)/\(path)"
    components.queryItems = !queryItems.isEmpty ? queryItems : nil

    guard let generatedUrl = components.url else {
      throw URLError(.badURL)
    }

    return generatedUrl
  }

  /// Returns the public URL for a file in a public bucket, with a boolean download trigger.
  ///
  /// This overload is a convenience variant of
  /// ``getPublicURL(path:download:options:cacheNonce:)`` that accepts a `Bool` instead of an
  /// optional file name string. When `download` is `true`, the browser uses the original file
  /// name for the download prompt.
  ///
  /// - Parameters:
  ///   - path: The path of the file within the bucket, e.g. `"folder/image.png"`.
  ///   - download: Pass `true` to trigger a browser download using the original file name.
  ///   - options: Optional on-the-fly image transformation applied when the URL is fetched.
  ///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter for cache
  ///     invalidation.
  /// - Returns: The public `URL` for the file.
  /// - Throws: `URLError(.badURL)` if the resulting URL cannot be constructed.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let url = try storage.from("documents").getPublicURL(path: "report.pdf", download: true)
  /// ```
  public func getPublicURL(
    path: String,
    download: Bool,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    try getPublicURL(
      path: path,
      download: download ? "" : nil,
      options: options,
      cacheNonce: cacheNonce
    )
  }

  /// Creates a signed upload URL for uploading a file without further authentication.
  ///
  /// Signed upload URLs are valid for **2 hours** and allow anyone in possession of the URL to
  /// upload a file to the specified path. This is useful for client-side uploads where you do not
  /// want to expose Storage credentials.
  ///
  /// After calling this method, pass the returned ``SignedUploadURL/token`` to
  /// ``uploadToSignedURL(_:token:data:options:)`` or
  /// ``uploadToSignedURL(_:token:fileURL:options:)`` to perform the actual upload.
  ///
  /// - Parameters:
  ///   - path: The destination path within the bucket, e.g. `"user-123/upload.png"`.
  ///   - options: Optional overrides, such as enabling upsert behaviour.
  /// - Returns: A ``SignedUploadURL`` containing the signed URL, path, and extracted token.
  /// - Throws: ``StorageError`` if the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let signed = try await storage.from("uploads").createSignedUploadURL(path: "user-123/photo.png")
  ///
  /// // Later, upload the file using the signed token
  /// try await storage.from("uploads").uploadToSignedURL(
  ///   signed.path,
  ///   token: signed.token,
  ///   data: imageData,
  ///   options: FileOptions(contentType: "image/png")
  /// )
  /// ```
  public func createSignedUploadURL(
    path: String,
    options: CreateSignedUploadURLOptions? = nil
  ) async throws -> SignedUploadURL {
    struct Response: Decodable {
      let url: String
    }

    var headers = [String: String]()
    if let upsert = options?.upsert, upsert {
      headers[Header.xUpsert] = "true"
    }

    let response: Response = try await client.fetchDecoded(
      .post,
      "object/upload/sign/\(bucketId)/\(path)",
      headers: headers
    )

    let signedURL = try makeSignedURL(response.url, download: nil)

    guard
      let components = URLComponents(
        url: signedURL,
        resolvingAgainstBaseURL: false
      )
    else {
      throw URLError(.badURL)
    }

    guard
      let token = components.queryItems?.first(where: { $0.name == "token" })?
        .value
    else {
      throw StorageError(
        statusCode: nil,
        message: "No token returned by API",
        error: nil
      )
    }

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    return SignedUploadURL(
      signedURL: url,
      path: path,
      token: token
    )
  }

  /// Uploads `Data` to a path using a token obtained from ``createSignedUploadURL(path:options:)``.
  ///
  /// The token must match the path and must not have expired (signed upload URLs are valid for
  /// 2 hours).
  ///
  /// - Parameters:
  ///   - path: The destination path within the bucket, matching the path used when the token
  ///     was created.
  ///   - token: The upload token from ``SignedUploadURL/token``.
  ///   - data: The raw file bytes to store.
  ///   - options: Upload options such as content type and cache duration.
  /// - Returns: A ``SignedURLUploadResponse`` containing the path and full storage key.
  /// - Throws: ``StorageError`` if the token is invalid or expired, or if the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let signed = try await storage.from("uploads").createSignedUploadURL(path: "file.pdf")
  /// let response = try await storage.from("uploads").uploadToSignedURL(
  ///   signed.path,
  ///   token: signed.token,
  ///   data: pdfData,
  ///   options: FileOptions(contentType: "application/pdf")
  /// )
  /// print(response.fullPath)
  /// ```
  @discardableResult
  public func uploadToSignedURL(
    _ path: String,
    token: String,
    data: Data,
    options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    try await _uploadToSignedURL(
      path: path,
      token: token,
      file: .data(data),
      options: options
    )
  }

  /// Uploads a file from a local `URL` to a path using a token obtained from
  /// ``createSignedUploadURL(path:options:)``.
  ///
  /// For files ≥ 10 MB the SDK automatically streams from a temporary file on disk to avoid
  /// loading the entire payload into memory.
  ///
  /// - Parameters:
  ///   - path: The destination path within the bucket, matching the path used when the token
  ///     was created.
  ///   - token: The upload token from ``SignedUploadURL/token``.
  ///   - fileURL: A local `file://` URL pointing to the file to upload.
  ///   - options: Upload options such as content type and cache duration.
  ///     When `contentType` is `nil`, the MIME type is inferred from the file extension.
  /// - Returns: A ``SignedURLUploadResponse`` containing the path and full storage key.
  /// - Throws: ``StorageError`` if the token is invalid or expired, or if the request fails.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let fileURL = URL(fileURLWithPath: "/tmp/video.mp4")
  /// let signed = try await storage.from("uploads").createSignedUploadURL(path: "user-123/video.mp4")
  /// let response = try await storage.from("uploads").uploadToSignedURL(
  ///   signed.path,
  ///   token: signed.token,
  ///   fileURL: fileURL
  /// )
  /// ```
  @discardableResult
  public func uploadToSignedURL(
    _ path: String,
    token: String,
    fileURL: URL,
    options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    try await _uploadToSignedURL(
      path: path,
      token: token,
      file: .url(fileURL),
      options: options
    )
  }

  private func _uploadToSignedURL(
    path: String,
    token: String,
    file: FileUpload,
    options: FileOptions?
  ) async throws -> SignedURLUploadResponse {
    let options = options ?? file.defaultOptions()
    var headers = multipartHeaders(options: options)
    headers[Header.xUpsert] = "\(options.upsert)"

    let response: SignedUploadResponse = try await uploadMultipart(
      .put,
      url: storageURL(
        path: "object/upload/sign/\(bucketId)/\(path)",
        queryItems: [URLQueryItem(name: "token", value: token)]
      ),
      path: path,
      file: file,
      options: options,
      headers: headers
    )

    return SignedURLUploadResponse(path: path, fullPath: response.Key)
  }

  private func uploadMultipart<Response: Decodable>(
    _ method: HTTPMethod,
    url: URL,
    path: String,
    file: FileUpload,
    options: FileOptions,
    headers: [String: String]
  ) async throws -> Response {
    #if DEBUG
      let builder = MultipartBuilder(
        boundary: testingBoundary.value ?? "----sb-\(UUID().uuidString)")
    #else
      let builder = MultipartBuilder()
    #endif

    let multipart = file.append(
      to: builder,
      withPath: path,
      options: options
    )

    var headers = headers
    headers[Header.contentType] = multipart.contentType

    let request = try await client.http.createRequest(
      method,
      url: url,
      headers: client.mergedHeaders(headers)
    )

    do {
      client.logRequest(method, url: url)
      let data: Data
      let response: URLResponse

      if try file.usesTempFileUpload {
        let tempFile = try multipart.buildToTempFile()
        defer { try? FileManager.default.removeItem(at: tempFile) }

        (data, response) = try await client.http.session.upload(
          for: request,
          fromFile: tempFile
        )
      } else {
        (data, response) = try await client.http.session.upload(
          for: request,
          from: try multipart.buildInMemory()
        )
      }

      let httpResponse = try client.http.validateResponse(response, data: data)
      client.logResponse(httpResponse, data: data)
      return try client.decoder.decode(Response.self, from: data)
    } catch {
      client.logFailure(error)
      throw translateStorageError(error)
    }
  }

  private func multipartHeaders(options: FileOptions) -> [String: String] {
    var headers = options.headers ?? [:]
    headers.setIfMissing(Header.cacheControl, value: "max-age=\(options.cacheControl)")

    if let duplex = options.duplex {
      headers[Header.duplex] = duplex
    }

    return headers
  }

  private func storageURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    var components = URLComponents(
      url: client.url.appendingPathComponent(path),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = queryItems.isEmpty ? nil : queryItems

    guard let url = components?.url else {
      throw URLError(.badURL)
    }

    return url
  }

  private func translateStorageError(_ error: any Error) -> any Error {
    guard case HTTPClientError.responseError(let response, let data) = error else {
      return error
    }

    if let storageError = try? client.decoder.decode(StorageError.self, from: data) {
      return storageError
    }

    return HTTPError(data: data, response: response)
  }

  private func _getFinalPath(_ path: String) -> String {
    "\(bucketId)/\(path)"
  }
}

func _removeEmptyFolders(_ path: String) -> String {
  let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  let cleanedPath = trimmedPath.replacingOccurrences(
    of: "/+",
    with: "/",
    options: .regularExpression
  )
  return cleanedPath
}

extension [String: String] {
  fileprivate mutating func setIfMissing(_ key: String, value: String) {
    guard keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) == nil else {
      return
    }

    self[key] = value
  }
}
