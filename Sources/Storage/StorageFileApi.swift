public import Foundation
public import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@available(*, deprecated)
let defaultSearchOptions = SearchOptions(
  limit: 100,
  offset: 0,
  sortBy: SortBy(
    column: "name",
    order: "asc"
  )
)

enum FileUpload {
  case data(Data)
  case url(URL)

  func encode(to formData: MultipartFormData, withPath path: String, options: UploadParameters) {
    if let cacheControl = options.cacheControlField {
      formData.append(
        cacheControl.data(using: .utf8)!,
        withName: "cacheControl"
      )
    }

    if let metadata = options.metadata {
      formData.append(encodeMetadata(metadata), withName: "metadata")
    }

    switch self {
    case .data(let data):
      formData.append(
        data,
        withName: "",
        fileName: path.fileName,
        mimeType: options.contentType ?? mimeType(forPathExtension: path.pathExtension)
      )

    case .url(let url):
      formData.append(
        url,
        withName: "",
        fileName: url.lastPathComponent,
        mimeType: options.contentType ?? mimeType(forPathExtension: url.pathExtension)
      )
    }
  }
}

#if DEBUG
  import ConcurrencyExtras
  let testingBoundary = LockIsolated<String?>(nil)
#endif

/// Supabase Storage File API for file operations within a specific bucket.
///
/// Obtain a ``StorageFileApi`` by calling ``SupabaseStorageClient/from(_:)`` with the bucket
/// identifier you want to operate on:
///
/// ```swift
/// let fileApi = storage.from("avatars")
///
/// // Upload a PNG
/// try await fileApi.upload(path: "user123.png", data: imageData)
///
/// // Generate a signed URL valid for 60 seconds
/// let url = try await fileApi.createSignedURL(path: "user123.png", expiresIn: .seconds(60))
/// ```
///
/// > Note: This class is `@unchecked Sendable`. The ``id`` property is immutable, and
/// > all mutable header state is protected by the lock inherited from ``StorageApi``.
///
/// ## Topics
///
/// ### Identifying the bucket
///
/// - ``id``
///
/// ### Customizing headers
///
/// - ``settingHeader(name:value:)``
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
/// - ``createSignedUploadURL(path:upsert:)``
/// - ``uploadToSignedURL(path:token:data:options:)``
/// - ``uploadToSignedURL(path:token:fileURL:options:)``
///
/// ### Downloading files
///
/// - ``download(path:options:query:cacheNonce:)``
/// - ``publicURL(path:options:)``
///
/// ### Managing files
///
/// - ``move(from:to:options:)``
/// - ``copy(from:to:options:)``
/// - ``remove(paths:)``
/// - ``list(path:options:)``
/// - ``info(path:)``
/// - ``exists(path:)``
///
/// ### Creating signed URLs
///
/// - ``createSignedURL(path:expiresIn:options:)``
/// - ``createSignedURLs(paths:expiresIn:options:)``
public class StorageFileApi: StorageApi, @unchecked Sendable {
  let bucketId: String

  /// The identifier of the bucket this instance operates on.
  public var id: String { bucketId }

  init(bucketId: String, configuration: StorageClientConfiguration) {
    self.bucketId = bucketId
    super.init(configuration: configuration)
  }

  /// Returns a new instance for the same bucket with an additional HTTP header, included in all
  /// requests made by the returned instance.
  ///
  /// This method does not change the receiver. Always use the result:
  ///
  /// ```swift
  /// let bucket = storage.from("avatars").settingHeader(
  ///   name: .init("X-Custom-Header")!, value: "x-custom-header")
  /// ```
  ///
  /// - Parameters:
  ///   - name: The header field. Names match case-insensitively.
  ///   - value: The value of the header field.
  /// - Returns: A new instance with the header merged into the configuration's headers.
  public func settingHeader(name: HTTPField.Name, value: String) -> StorageFileApi {
    StorageFileApi(
      bucketId: bucketId, configuration: configuration(settingHeader: name, to: value))
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

  private struct UploadResult {
    let id: String
    let path: String
    let fullPath: String
  }

  private func _uploadOrUpdate(
    method: HTTPTypes.HTTPRequest.Method,
    path: String,
    file: FileUpload,
    options: UploadParameters
  ) async throws -> UploadResult {
    var headers = options.headers

    if method == .post {
      headers[.xUpsert] = "\(options.upsert)"
    }

    headers[.duplex] = options.duplex

    #if DEBUG
      let formData = MultipartFormData(boundary: testingBoundary.value)
    #else
      let formData = MultipartFormData()
    #endif
    file.encode(to: formData, withPath: path, options: options)

    struct UploadResponse: Decodable {
      let Key: String
      let Id: String
    }

    let cleanPath = _removeEmptyFolders(path)
    let _path = _getFinalPath(cleanPath)

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/\(_path)"),
        method: method,
        query: [],
        formData: formData,
        cacheControl: options.cacheControlHeader,
        headers: headers
      )
    )
    .decoded(as: UploadResponse.self, decoder: configuration.decoder)

    return UploadResult(
      id: response.Id,
      path: cleanPath,
      fullPath: response.Key
    )
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
  /// - Returns: An ``UploadedObject`` containing the stored object's identifier and path.
  /// - Throws: ``StorageError`` if the upload fails or the caller is not authorized.
  @discardableResult
  public func upload(
    path: String,
    data: Data,
    options: UploadOptions = UploadOptions()
  ) async throws -> UploadedObject {
    try await _upload(method: .post, path: path, file: .data(data), options: options)
  }

  /// Uploads a file from a local file URL to an existing bucket.
  ///
  /// Use this overload when you have a `URL` pointing to a file on disk rather than raw `Data`
  /// already loaded in memory.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to upload.
  ///   - fileURL: A `file://` URL pointing to the local file to upload.
  ///   - options: Upload options such as cache control, content type, and upsert behavior.
  /// - Returns: An ``UploadedObject`` containing the stored object's identifier and path.
  /// - Throws: ``StorageError`` if the upload fails or the caller is not authorized.
  @discardableResult
  public func upload(
    path: String,
    fileURL: URL,
    options: UploadOptions = UploadOptions()
  ) async throws -> UploadedObject {
    try await _upload(method: .post, path: path, file: .url(fileURL), options: options)
  }

  /// Replaces an existing file at the specified path with new data.
  ///
  /// Unlike ``upload(path:data:options:)`` with `upsert: true`, this method always targets an
  /// existing object and will throw if the path does not exist.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to update.
  ///   - data: The raw bytes to overwrite the existing file with.
  ///   - options: Upload options such as cache control and content type. `upsert` is ignored:
  ///     `update` always replaces the object.
  /// - Returns: An ``UploadedObject`` containing the updated object's identifier and path.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @discardableResult
  public func update(
    path: String,
    data: Data,
    options: UploadOptions = UploadOptions()
  ) async throws -> UploadedObject {
    try await _upload(method: .put, path: path, file: .data(data), options: options)
  }

  /// Replaces an existing file at the specified path with a new local file.
  ///
  /// Use this overload when the replacement content is available as a `URL` pointing to a file on
  /// disk rather than raw `Data`.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to update.
  ///   - fileURL: A `file://` URL pointing to the local file to use as the replacement.
  ///   - options: Upload options such as cache control and content type. `upsert` is ignored:
  ///     `update` always replaces the object.
  /// - Returns: An ``UploadedObject`` containing the updated object's identifier and path.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @discardableResult
  public func update(
    path: String,
    fileURL: URL,
    options: UploadOptions = UploadOptions()
  ) async throws -> UploadedObject {
    try await _upload(method: .put, path: path, file: .url(fileURL), options: options)
  }

  private func _upload(
    method: HTTPTypes.HTTPRequest.Method,
    path: String,
    file: FileUpload,
    options: UploadOptions
  ) async throws -> UploadedObject {
    let result = try await _uploadOrUpdate(
      method: method, path: path, file: file, options: UploadParameters(options))
    return UploadedObject(
      id: UUID(uuidString: result.id), path: result.path, fullPath: result.fullPath)
  }

  /// Uploads a file to an existing bucket.
  ///
  /// ```swift
  /// let response = try await storage.from("avatars").upload("user123.png", data: imageData)
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
  @available(*, deprecated, message: "Use upload(path:data:options:) instead.")
  @discardableResult
  public func upload(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    let result = try await _uploadOrUpdate(
      method: .post,
      path: path,
      file: .data(data),
      options: UploadParameters(options)
    )
    return FileUploadResponse(id: result.id, path: result.path, fullPath: result.fullPath)
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
  @available(*, deprecated, message: "Use upload(path:fileURL:options:) instead.")
  @discardableResult
  public func upload(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    let result = try await _uploadOrUpdate(
      method: .post,
      path: path,
      file: .url(fileURL),
      options: UploadParameters(options)
    )
    return FileUploadResponse(id: result.id, path: result.path, fullPath: result.fullPath)
  }

  /// Replaces an existing file at the specified path with new data.
  ///
  /// Unlike ``upload(_:data:options:)`` with `upsert: true`, this method always targets an
  /// existing object and will throw if the path does not exist.
  ///
  /// - Parameters:
  ///   - path: The relative file path within the bucket, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist before attempting to update.
  ///   - data: The raw bytes to overwrite the existing file with.
  ///   - options: Upload options such as cache control and content type.
  /// - Returns: A ``FileUploadResponse`` containing the updated object's identifier and path.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  @available(*, deprecated, message: "Use update(path:data:options:) instead.")
  @discardableResult
  public func update(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    let result = try await _uploadOrUpdate(
      method: .put,
      path: path,
      file: .data(data),
      options: UploadParameters(options)
    )
    return FileUploadResponse(id: result.id, path: result.path, fullPath: result.fullPath)
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
  @available(*, deprecated, message: "Use update(path:fileURL:options:) instead.")
  @discardableResult
  public func update(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    let result = try await _uploadOrUpdate(
      method: .put,
      path: path,
      file: .url(fileURL),
      options: UploadParameters(options)
    )
    return FileUploadResponse(id: result.id, path: result.path, fullPath: result.fullPath)
  }

  private struct CopyBody: Encodable {
    struct Metadata: Encodable {
      let cacheControl: String?
      let mimetype: String?
    }

    let bucketID: String
    let sourceKey: String
    let destinationKey: String
    let destinationBucket: String?
    let sourceVersionID: String?
    var copyMetadata: Bool?
    var metadata: Metadata?

    enum CodingKeys: String, CodingKey {
      case bucketID = "bucketId"
      case sourceKey
      case destinationKey
      case destinationBucket
      case sourceVersionID = "sourceVersionId"
      case copyMetadata
      case metadata
    }
  }

  private struct CopyResponse: Decodable {
    let key: String
    let id: String?

    enum CodingKeys: String, CodingKey {
      case key = "Key"
      case id = "Id"
    }
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
  ///   - sourceVersionID: The version of the source to move. `nil` moves the current version.
  /// - Throws: ``StorageError`` if the source does not exist or the caller is not authorized.
  public func move(
    from source: String,
    to destination: String,
    toBucket: String? = nil,
    sourceVersionID: String? = nil
  ) async throws {
    var body: [String: String?] = [
      "bucketId": bucketId,
      "sourceKey": source,
      "destinationKey": destination,
      "destinationBucket": toBucket,
    ]
    if let sourceVersionID {
      body["sourceVersionId"] = sourceVersionID
    }

    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/move"),
        method: .post,
        body: configuration.encoder.encode(body)
      )
    )
  }

  /// Moves an existing file to a new path, optionally within a different bucket.
  ///
  /// - Parameters:
  ///   - source: The original file path including the file name, e.g. `"folder/image.png"`.
  ///   - destination: The new file path including the new file name, e.g. `"archive/image.png"`.
  ///   - options: Optional ``DestinationOptions`` specifying a destination bucket. When `nil`,
  ///     the file is moved within the same bucket.
  /// - Throws: ``StorageError`` if the source does not exist or the caller is not authorized.
  @available(*, deprecated, message: "Use move(from:to:toBucket:sourceVersionID:) instead.")
  @_disfavoredOverload
  public func move(
    from source: String,
    to destination: String,
    options: DestinationOptions? = nil
  ) async throws {
    try await move(from: source, to: destination, toBucket: options?.destinationBucket)
  }

  /// Copies an existing file to a new path, optionally within a different bucket.
  ///
  /// ```swift
  /// let copy = try await storage.from("docs").copy(
  ///   from: "original.pdf", to: "backup/original.pdf", options: CopyOptions(upsert: true))
  /// print(copy.fullPath)  // "docs/backup/original.pdf"
  /// ```
  ///
  /// A call with only `from` and `to` selects the deprecated overload that returns a `String`,
  /// unless the context asks for an ``UploadedObject``.
  ///
  /// - Parameters:
  ///   - source: The original file path including the file name, e.g. `"folder/image.png"`.
  ///   - destination: The destination path including the new file name, e.g. `"folder/image-copy.png"`.
  ///   - toBucket: The bucket to copy the file into. `nil` copies it within this bucket.
  ///   - sourceVersionID: The version of the source to copy. `nil` copies the current version.
  ///   - options: Whether to replace an existing destination, and the metadata of the copy.
  /// - Returns: The copy's identifier and path.
  /// - Throws: ``StorageError`` if the source does not exist, the destination exists and
  ///   ``CopyOptions/upsert`` is `false`, or the caller is not authorized.
  @_disfavoredOverload
  @discardableResult
  public func copy(
    from source: String,
    to destination: String,
    toBucket: String? = nil,
    sourceVersionID: String? = nil,
    options: CopyOptions = CopyOptions()
  ) async throws -> UploadedObject {
    var body = CopyBody(
      bucketID: bucketId, sourceKey: source, destinationKey: destination,
      destinationBucket: toBucket, sourceVersionID: sourceVersionID)
    if !options.copyMetadata {
      body.copyMetadata = false
    }
    if options.cacheControl != nil || options.contentType != nil {
      body.metadata = CopyBody.Metadata(
        cacheControl: options.cacheControl?.rawValue, mimetype: options.contentType)
    }

    var headers = HTTPFields()
    if options.upsert {
      headers[.xUpsert] = "true"
    }
    if let metadata = options.metadata {
      headers[.xMetadata] = encodeMetadata(metadata).base64EncodedString()
    }

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/copy"),
        method: .post,
        headers: headers,
        body: JSONEncoder.unconfiguredEncoder.encode(body)
      )
    )
    .decoded(as: CopyResponse.self, decoder: configuration.decoder)

    return UploadedObject(
      id: response.id.flatMap(UUID.init(uuidString:)), path: destination, fullPath: response.key)
  }

  /// Copies an existing file to a new path, optionally within a different bucket.
  ///
  /// - Parameters:
  ///   - source: The original file path including the file name, e.g. `"folder/image.png"`.
  ///   - destination: The destination path including the new file name, e.g. `"folder/image-copy.png"`.
  ///   - options: Optional ``DestinationOptions`` specifying a destination bucket. When `nil`,
  ///     the file is copied within the same bucket.
  /// - Returns: The full storage path of the newly created copy.
  /// - Throws: ``StorageError`` if the source does not exist or the caller is not authorized.
  @available(
    *, deprecated,
    message:
      "Use copy(from:to:toBucket:sourceVersionID:options:) instead. The old result is UploadedObject.fullPath."
  )
  @discardableResult
  public func copy(
    from source: String,
    to destination: String,
    options: DestinationOptions? = nil
  ) async throws -> String {
    struct UploadResponse: Decodable {
      let Key: String
    }

    return try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/copy"),
        method: .post,
        body: configuration.encoder.encode(
          [
            "bucketId": bucketId,
            "sourceKey": source,
            "destinationKey": destination,
            "destinationBucket": options?.destinationBucket,
          ]
        )
      )
    )
    .decoded(as: UploadResponse.self, decoder: configuration.decoder)
    .Key
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
  @available(
    *, deprecated,
    message:
      "Use createSignedURL(path:expiresIn:options:) with a Duration and SignedURLOptions instead."
  )
  @_disfavoredOverload
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: String? = nil,
    transform: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) async throws -> URL {
    try await _createSignedURL(
      path: path, expiresIn: expiresIn, transform: transform, versionID: nil, download: download,
      cacheNonce: cacheNonce)
  }

  private struct SignBody<Transform: Encodable>: Encodable {
    let expiresIn: Int
    let transform: Transform?
    let versionId: String?
  }

  private func _createSignedURL(
    path: String,
    expiresIn: Int,
    transform: (some Encodable)?,
    versionID: String?,
    download: String?,
    cacheNonce: String?
  ) async throws -> URL {
    let encoder = JSONEncoder.unconfiguredEncoder

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/sign/\(_getFinalPath(path))"),
        method: .post,
        body: encoder.encode(
          SignBody(expiresIn: expiresIn, transform: transform, versionId: versionID)
        )
      )
    )
    .decoded(as: SignedURLAPIResponse.self, decoder: configuration.decoder)

    return try makeSignedURL(response.signedURL, download: download, cacheNonce: cacheNonce)
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
  ///   options: SignedURLOptions(download: .withOriginalName)
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - expiresIn: How long the URL stays valid, e.g. `.seconds(60)`. Whole seconds are sent;
  ///     less than one second throws ``StorageError`` with kind `invalidRequest`.
  ///   - options: The download behavior, image transformation, version and cache nonce.
  /// - Returns: A signed `URL` ready to share.
  /// - Throws: ``StorageError`` if the path does not exist or the caller is not authorized.
  public func createSignedURL(
    path: String,
    expiresIn: Duration,
    options: SignedURLOptions = SignedURLOptions()
  ) async throws -> URL {
    try await _createSignedURL(
      path: path,
      expiresIn: Self.seconds(expiresIn),
      transform: options.transform?.isEmpty == false ? options.transform?.body : nil,
      versionID: options.versionID,
      download: options.download?.queryValue,
      cacheNonce: options.cacheNonce)
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
  @available(
    *, deprecated,
    message:
      "Use createSignedURL(path:expiresIn:options:) with a Duration and SignedURLOptions instead."
  )
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
  @available(
    *, deprecated,
    message:
      "Use createSignedURLs(paths:expiresIn:options:) with a Duration and SignedURLsOptions instead."
  )
  @_disfavoredOverload
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: String? = nil,
    cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    try await _createSignedURLs(
      paths: paths, expiresIn: expiresIn, download: download, cacheNonce: cacheNonce)
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
  ///   - options: The download behavior and cache nonce.
  /// - Returns: An array of ``SignedURLResult`` values, one per requested path, preserving order.
  /// - Throws: ``StorageError`` if the request itself fails (e.g. unauthorized). Individual missing
  ///   paths are reported as ``SignedURLResult/failure(path:error:)`` rather than thrown.
  public func createSignedURLs(
    paths: [String],
    expiresIn: Duration,
    options: SignedURLsOptions = SignedURLsOptions()
  ) async throws -> [SignedURLResult] {
    try await _createSignedURLs(
      paths: paths, expiresIn: Self.seconds(expiresIn), download: options.download?.queryValue,
      cacheNonce: options.cacheNonce)
  }

  private func _createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: String?,
    cacheNonce: String?
  ) async throws -> [SignedURLResult] {
    struct Params: Encodable {
      let expiresIn: Int
      let paths: [String]
    }

    let encoder = JSONEncoder.unconfiguredEncoder

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/sign/\(bucketId)"),
        method: .post,
        body: encoder.encode(
          Params(expiresIn: expiresIn, paths: paths)
        )
      )
    )
    .decoded(as: [SignedURLsAPIResponse].self, decoder: configuration.decoder)

    return try response.map { item in
      if let signedURLString = item.signedURL {
        let url = try makeSignedURL(signedURLString, download: download, cacheNonce: cacheNonce)
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
  @available(
    *, deprecated,
    message:
      "Use createSignedURLs(paths:expiresIn:options:) with a Duration and SignedURLsOptions instead."
  )
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

  /// Creates multiple signed URLs. Use a signed URL to share a file for a fixed amount of time.
  ///
  /// Each item in the returned array is a ``SignedURLResult``: either `.success(path:signedURL:)` or
  /// `.failure(path:error:)`. Exactly one case is guaranteed per item.
  /// - Parameters:
  ///   - paths: The file paths to be downloaded, including the current file names. For example `["folder/image.png", "folder2/image2.png"]`.
  ///   - expiresIn: The number of seconds until the signed URLs expire. For example, `60` for URLs which are valid for one minute.
  ///   - download: Trigger a download with the default file name.
  ///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
  private func makeSignedURL(_ signedURL: String, download: String?, cacheNonce: String? = nil)
    throws -> URL
  {
    guard let signedURLComponents = URLComponents(string: signedURL),
      var baseComponents = URLComponents(
        url: configuration.url, resolvingAgainstBaseURL: false)
    else {
      throw URLError(.badURL)
    }

    baseComponents.path +=
      signedURLComponents.path.hasPrefix("/")
      ? signedURLComponents.path : "/\(signedURLComponents.path)"
    baseComponents.queryItems = signedURLComponents.queryItems

    if let download {
      baseComponents.queryItems = baseComponents.queryItems ?? []
      baseComponents.queryItems!.append(URLQueryItem(name: "download", value: download))
    }

    if let cacheNonce {
      baseComponents.queryItems = baseComponents.queryItems ?? []
      baseComponents.queryItems!.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
    }

    guard let signedURL = baseComponents.url else {
      throw URLError(.badURL)
    }

    return signedURL
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
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/\(bucketId)"),
        method: .delete,
        body: configuration.encoder.encode(["prefixes": paths])
      )
    )
    .decoded(decoder: configuration.decoder)
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
  @available(
    *, deprecated,
    message: "Use list(path:options:) with ListOptions instead. It returns [StorageObject]."
  )
  public func list(
    path: String? = nil,
    options: SearchOptions? = nil
  ) async throws -> [FileObject] {
    let encoder = JSONEncoder.unconfiguredEncoder

    var options = options ?? defaultSearchOptions
    options.limit = options.limit ?? defaultSearchOptions.limit
    options.offset = options.offset ?? defaultSearchOptions.offset
    options.prefix = path ?? ""

    var sortBy = options.sortBy ?? SortBy()
    sortBy.column = sortBy.column ?? defaultSearchOptions.sortBy?.column
    sortBy.order = sortBy.order ?? defaultSearchOptions.sortBy?.order
    options.sortBy = sortBy

    return try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/list/\(bucketId)"),
        method: .post,
        body: encoder.encode(options)
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  private struct ListBody: Encodable {
    struct Sort: Encodable {
      let column: String
      let order: String
    }

    let prefix: String
    let limit: Int
    let offset: Int
    let sortBy: Sort
    let search: String?
    let exactMatch: Bool?
    let noncurrentVersions: String?
    let deleteMarkers: String?
  }

  /// Lists all files within a bucket folder.
  ///
  /// ```swift
  /// let files = try await storage.from("avatars").list(
  ///   path: "users/", options: ListOptions(sortBy: .updatedAt, order: .descending))
  /// ```
  ///
  /// A call without `options` selects the deprecated overload that returns ``FileObject`` values,
  /// unless the context asks for ``StorageObject`` values.
  ///
  /// - Parameters:
  ///   - path: The folder prefix to list, e.g. `"users/"`. Pass `nil` to list the bucket root.
  ///   - options: Paging, sort and filters. Defaults to the first 100 entries sorted by name
  ///     ascending.
  /// - Returns: The files and folders one level under `path`, with names relative to it. A
  ///   folder is an entry whose ``StorageObject/isFolder`` is `true`.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  @_disfavoredOverload
  public func list(
    path: String? = nil,
    options: ListOptions = ListOptions()
  ) async throws -> [StorageObject] {
    let body = ListBody(
      prefix: path ?? "",
      limit: options.limit ?? 100,
      offset: options.offset ?? 0,
      sortBy: ListBody.Sort(
        column: (options.sortBy ?? .name).rawValue,
        order: (options.order ?? .ascending).rawValue),
      search: options.search,
      exactMatch: options.exactMatch,
      noncurrentVersions: options.versions?.rawValue,
      deleteMarkers: options.deleteMarkers?.rawValue)

    return try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/list/\(bucketId)"),
        method: .post,
        body: JSONEncoder.unconfiguredEncoder.encode(body)
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Downloads a file from a private bucket and returns its raw bytes.
  ///
  /// For public buckets, prefer requesting the URL returned by
  /// ``publicURL(path:options:)`` directly.
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
    var queryItems = options?.queryItems ?? []
    let renderPath = options.map { !$0.isEmpty } == true ? "render/image/authenticated" : "object"
    let _path = _getFinalPath(path)

    if let additionalQueryItems {
      queryItems.append(contentsOf: additionalQueryItems)
    }

    if let cacheNonce {
      queryItems.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
    }

    return try await execute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("\(renderPath)/\(_path)"),
        method: .get,
        query: queryItems
      )
    )
    .data
  }

  /// Retrieves metadata about an existing file without downloading its content.
  ///
  /// - Parameter path: The file path including the file name, e.g. `"folder/image.png"`.
  /// - Returns: A ``FileObjectV2`` containing size, content type, ETag, and other metadata.
  /// - Throws: ``StorageError`` if the file does not exist or the caller is not authorized.
  @available(*, deprecated, message: "Use info(path:versionID:) instead. It returns ObjectInfo.")
  public func info(path: String) async throws -> FileObjectV2 {
    try await _info(path: path, versionID: nil)
  }

  /// Retrieves metadata about an existing file without downloading its content.
  ///
  /// A call with only `path` selects the deprecated overload that returns ``FileObjectV2``,
  /// unless the context asks for an ``ObjectInfo``.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - versionID: The version to describe. `nil` describes the current version.
  /// - Returns: An ``ObjectInfo`` containing size, content type, ETag, and other metadata.
  /// - Throws: ``StorageError`` if the file does not exist or the caller is not authorized.
  @_disfavoredOverload
  public func info(path: String, versionID: String? = nil) async throws -> ObjectInfo {
    try await _info(path: path, versionID: versionID)
  }

  private func _info<Info: Decodable>(path: String, versionID: String?) async throws -> Info {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/info/\(_getFinalPath(path))"),
        method: .get,
        query: versionID.map { [URLQueryItem(name: "versionId", value: $0)] } ?? []
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Checks whether a file exists in the bucket without downloading it.
  ///
  /// Returns `false` for HTTP 400 and 404 responses, and re-throws for any other error.
  ///
  /// - Parameter path: The file path including the file name, e.g. `"folder/image.png"`.
  /// - Returns: `true` if the file exists and is accessible, `false` if it does not exist.
  /// - Throws: ``StorageError`` for errors other than "not found" (e.g. network failure or
  ///   authorization errors).
  public func exists(path: String) async throws -> Bool {
    do {
      try await execute(
        HTTPRequest(
          url: configuration.url.appendingPathComponent("object/\(_getFinalPath(path))"),
          method: .head
        )
      )
      return true
    } catch {
      var statusCode: Int?

      if let error = error as? StorageError {
        statusCode = error.serverError?.statusCode
      } else if let error = error as? HTTPError {
        statusCode = error.response.statusCode
      }

      if let statusCode, [400, 404].contains(statusCode) {
        return false
      }

      throw error
    }
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
  /// - Throws: `URLError` if the resulting URL cannot be constructed.
  @available(*, deprecated, message: "Use publicURL(path:options:) instead.")
  @_disfavoredOverload
  public func getPublicURL(
    path: String,
    download: String? = nil,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    guard
      let url = _publicURL(
        path: path, download: download, transform: options?.queryItems ?? [],
        cacheNonce: cacheNonce, versionID: nil
      ).built
    else {
      throw URLError(.badURL)
    }
    return url
  }

  /// A public URL built from URL components, and the same URL built by appending to the base
  /// URL, which cannot fail.
  private func _publicURL(
    path: String,
    download: String?,
    transform: [URLQueryItem],
    cacheNonce: String?,
    versionID: String?
  ) -> (built: URL?, appended: URL) {
    var queryItems: [URLQueryItem] = []

    if let download {
      queryItems.append(URLQueryItem(name: "download", value: download))
    }

    queryItems.append(contentsOf: transform)

    if let cacheNonce {
      queryItems.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
    }

    if let versionID {
      queryItems.append(URLQueryItem(name: "versionId", value: versionID))
    }

    let renderPath = transform.isEmpty ? "object" : "render/image"
    let route = "\(renderPath)/public/\(_getFinalPath(path))"
    let appended = configuration.url.appendingPathComponent(route).appendingQueryItems(queryItems)

    guard var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: true)
    else {
      return (nil, appended)
    }

    components.path += "/\(route)"
    components.queryItems = !queryItems.isEmpty ? queryItems : nil

    return (components.url, appended)
  }

  /// Returns the public URL for a file in a public bucket.
  ///
  /// ```swift
  /// // Inline display URL
  /// let url = storage.from("avatars").publicURL(path: "user123.png")
  ///
  /// // Force download with original file name
  /// let dlURL = storage.from("docs").publicURL(
  ///   path: "report.pdf", options: PublicURLOptions(download: .withOriginalName))
  /// ```
  ///
  /// > Note: The bucket must be set to public for this URL to be accessible without authentication.
  ///
  /// - Parameters:
  ///   - path: The file path including the file name, e.g. `"folder/image.png"`.
  ///   - options: The download behavior, image transformation, version and cache nonce.
  /// - Returns: The publicly accessible `URL` for the file.
  public func publicURL(
    path: String,
    options: PublicURLOptions = PublicURLOptions()
  ) -> URL {
    let url = _publicURL(
      path: path, download: options.download?.queryValue,
      transform: options.transform?.queryItems ?? [], cacheNonce: options.cacheNonce,
      versionID: options.versionID)
    return url.built ?? url.appended
  }

  /// Returns the public URL for a file in a public bucket.
  ///
  /// ```swift
  /// // Inline display URL
  /// let url = try storage.from("avatars").getPublicURL(path: "user123.png")
  ///
  /// // Force download with original file name
  /// let dlURL = try storage.from("docs").getPublicURL(path: "report.pdf", download: .withOriginalName)
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
  /// - Throws: `URLError` if the resulting URL cannot be constructed.
  @available(*, deprecated, message: "Use publicURL(path:options:) instead.")
  public func getPublicURL(
    path: String,
    download: DownloadBehavior? = nil,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    try getPublicURL(
      path: path,
      download: download?.queryValue,
      options: options,
      cacheNonce: cacheNonce
    )
  }

  /// Creates a signed upload URL that allows uploading a file without further authentication.
  ///
  /// Signed upload URLs are valid for 2 hours. Pass the returned ``SignedUploadURL/token`` to
  /// ``uploadToSignedURL(_:token:data:options:)`` (or the file-URL variant) to perform the upload.
  ///
  /// ```swift
  /// let signedUpload = try await storage.from("avatars").createSignedUploadURL(path: "user123.png")
  /// // Share signedUpload.token with the uploader
  /// try await storage.from("avatars").uploadToSignedURL(
  ///   "user123.png",
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
  @available(*, deprecated, message: "Use createSignedUploadURL(path:upsert:) instead.")
  @_disfavoredOverload
  public func createSignedUploadURL(
    path: String,
    options: CreateSignedUploadURLOptions? = nil
  ) async throws -> SignedUploadURL {
    try await createSignedUploadURL(path: path, upsert: options?.upsert ?? false)
  }

  /// Creates a signed upload URL that allows uploading a file without further authentication.
  ///
  /// Signed upload URLs are valid for 2 hours. Pass the returned ``SignedUploadURL/token`` to
  /// ``uploadToSignedURL(path:token:data:options:)`` (or the file-URL variant) to perform the
  /// upload.
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

    var headers = HTTPFields()
    if upsert {
      headers[.xUpsert] = "true"
    }

    let cleanPath = _removeEmptyFolders(path)

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent(
          "object/upload/sign/\(bucketId)/\(cleanPath)"),
        method: .post,
        headers: headers
      )
    )
    .decoded(as: Response.self, decoder: configuration.decoder)

    let signedURL = try makeSignedURL(response.url, download: nil)

    guard let components = URLComponents(url: signedURL, resolvingAgainstBaseURL: false) else {
      throw URLError(.badURL)
    }

    guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
      throw StorageError(kind: .decoding, message: "No token returned by API")
    }

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    return SignedUploadURL(
      signedURL: url,
      path: cleanPath,
      token: token
    )
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
  ///   - options: Optional upload options such as cache control and content type.
  /// - Returns: A ``SignedURLUploadResponse`` containing the stored object path.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @available(*, deprecated, message: "Use uploadToSignedURL(path:token:data:options:) instead.")
  @discardableResult
  public func uploadToSignedURL(
    _ path: String,
    token: String,
    data: Data,
    options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    let result = try await _uploadToSignedURL(
      path: path,
      token: token,
      file: .data(data),
      options: UploadParameters(options ?? FileOptions())
    )
    return SignedURLUploadResponse(path: result.path, fullPath: result.fullPath)
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
  ///   - options: Optional upload options such as cache control and content type.
  /// - Returns: A ``SignedURLUploadResponse`` containing the stored object path.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @available(*, deprecated, message: "Use uploadToSignedURL(path:token:fileURL:options:) instead.")
  @discardableResult
  public func uploadToSignedURL(
    _ path: String,
    token: String,
    fileURL: URL,
    options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    let result = try await _uploadToSignedURL(
      path: path,
      token: token,
      file: .url(fileURL),
      options: UploadParameters(options ?? FileOptions())
    )
    return SignedURLUploadResponse(path: result.path, fullPath: result.fullPath)
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
  ///   - options: Upload options such as cache control and content type. `upsert` has no effect:
  ///     the token decides whether an existing object is replaced.
  /// - Returns: An ``UploadedObject`` with the stored path; Storage returns no object id for a
  ///   signed-URL upload, so ``UploadedObject/id`` is `nil`.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    data: Data,
    options: UploadOptions = UploadOptions()
  ) async throws -> UploadedObject {
    let result = try await _uploadToSignedURL(
      path: path, token: token, file: .data(data), options: UploadParameters(options))
    return UploadedObject(id: nil, path: result.path, fullPath: result.fullPath)
  }

  /// Uploads a local file to a pre-signed upload URL.
  ///
  /// Obtain the `token` from ``createSignedUploadURL(path:upsert:)`` before calling this method.
  ///
  /// - Parameters:
  ///   - path: The destination file path, e.g. `"folder/subfolder/filename.png"`.
  ///     The bucket must already exist.
  ///   - token: The upload token from ``createSignedUploadURL(path:upsert:)``.
  ///   - fileURL: A `file://` URL pointing to the local file to upload.
  ///   - options: Upload options such as cache control and content type. `upsert` has no effect:
  ///     the token decides whether an existing object is replaced.
  /// - Returns: An ``UploadedObject`` with the stored path; Storage returns no object id for a
  ///   signed-URL upload, so ``UploadedObject/id`` is `nil`.
  /// - Throws: ``StorageError`` if the token is invalid, expired, or the upload fails.
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    fileURL: URL,
    options: UploadOptions = UploadOptions()
  ) async throws -> UploadedObject {
    let result = try await _uploadToSignedURL(
      path: path, token: token, file: .url(fileURL), options: UploadParameters(options))
    return UploadedObject(id: nil, path: result.path, fullPath: result.fullPath)
  }

  private func _uploadToSignedURL(
    path: String,
    token: String,
    file: FileUpload,
    options: UploadParameters
  ) async throws -> (path: String, fullPath: String) {
    var headers = options.headers

    headers[.xUpsert] = "\(options.upsert)"
    headers[.duplex] = options.duplex

    #if DEBUG
      let formData = MultipartFormData(boundary: testingBoundary.value)
    #else
      let formData = MultipartFormData()
    #endif
    file.encode(to: formData, withPath: path, options: options)

    struct UploadResponse: Decodable {
      let Key: String
    }

    let cleanPath = _removeEmptyFolders(path)

    let fullPath = try await execute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("object/upload/sign/\(bucketId)/\(cleanPath)"),
        method: .put,
        query: [URLQueryItem(name: "token", value: token)],
        formData: formData,
        cacheControl: options.cacheControlHeader,
        headers: headers
      )
    )
    .decoded(as: UploadResponse.self, decoder: configuration.decoder)
    .Key

    return (path: cleanPath, fullPath: fullPath)
  }

  private func _getFinalPath(_ path: String) -> String {
    let strippedPath = path.replacingOccurrences(
      of: "^/+", with: "", options: .regularExpression
    )
    return "\(bucketId)/\(strippedPath)"
  }

  private func _removeEmptyFolders(_ path: String) -> String {
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let cleanedPath = trimmedPath.replacingOccurrences(
      of: "/+", with: "/", options: .regularExpression
    )
    return cleanedPath
  }
}

extension HTTPField.Name {
  static let duplex = Self("duplex")!
  static let xUpsert = Self("x-upsert")!
  static let xMetadata = Self("x-metadata")!
}

/// Supabase Storage File API for file operations within a specific bucket.
///
/// The name ``StorageFileApi`` has in the next major version.
public typealias StorageBucket = StorageFileApi

extension UploadParameters {
  @available(*, deprecated, message: "Use init(_:) with UploadOptions instead.")
  init(_ options: FileOptions) {
    self.init(
      cacheControlField: options.cacheControl,
      cacheControlHeader: "max-age=\(options.cacheControl)",
      contentType: options.contentType,
      upsert: options.upsert,
      duplex: options.duplex,
      metadata: options.metadata,
      headers: options.headers.map { HTTPFields($0) } ?? HTTPFields()
    )
  }
}
