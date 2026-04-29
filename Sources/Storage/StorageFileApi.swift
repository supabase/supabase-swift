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
    order: "asc"
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

/// Supabase Storage File API for file operations within a bucket.
///
/// - Note: Thread Safety: Inherits immutable design from `StorageApi`. The additional `bucketId`
///   property is also immutable (`let`).
public struct StorageFileAPI {
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

  @available(macOS 10.15.4, *)
  @discardableResult
  public func uploadFile(
    _ fileURL: URL,
    to path: String,
    options: FileOptions? = nil
  ) async throws -> FileUploadResponse {
    try await upload(
      path, fileURL: fileURL, options: options ?? FileUpload.url(fileURL).defaultOptions())
  }

  /// Uploads a file to an existing bucket.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder/filename.png`. The bucket must already exist before attempting to upload.
  ///   - data: The Data to be stored in the bucket.
  ///   - options: The options for the uploaded file.
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

  /// Uploads a file to an existing bucket.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder/filename.png`. The bucket must already exist before attempting to upload.
  ///   - fileURL: The file URL to be stored in the bucket.
  ///   - options: The options for the uploaded file.
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

  /// Replaces an existing file at the specified path with a new one.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder`. The bucket already exist before attempting to upload.
  ///   - data: The Data to be stored in the bucket.
  ///   - options: The options for the updated file.
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

  /// Replaces an existing file at the specified path with a new one.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder`. The bucket already exist before attempting to upload.
  ///   - fileURL: The file URL to be stored in the bucket.
  ///   - options: The options for the updated file.
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

  /// Moves an existing file to a new path.
  /// - Parameters:
  ///   - source: The original file path, including the current file name. For example `folder/image.png`.
  ///   - destination: The new file path, including the new file name. For example `folder/image-new.png`.
  ///   - options: The destination options.
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

  /// Copies an existing file to a new path.
  /// - Parameters:
  ///   - source: The original file path, including the current file name. For example `folder/image.png`.
  ///   - destination: The new file path, including the new file name. For example `folder/image-copy.png`.
  ///   - options: The destination options.
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

  /// Creates a signed URL. Use a signed URL to share a file for a fixed amount of time.
  /// - Parameters:
  ///   - path: The file path, including the current file name. For example `folder/image.png`.
  ///   - expiresIn: The number of seconds until the signed URL expires. For example, `60` for a URL which is valid for one minute.
  ///   - download: Trigger a download with the specified file name.
  ///   - transform: Transform the asset before serving it to the client.
  ///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
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

  /// Creates a signed URL. Use a signed URL to share a file for a fixed amount of time.
  /// - Parameters:
  ///   - path: The file path, including the current file name. For example `folder/image.png`.
  ///   - expiresIn: The number of seconds until the signed URL expires. For example, `60` for a URL which is valid for one minute.
  ///   - download: Trigger a download with the default file name.
  ///   - transform: Transform the asset before serving it to the client.
  ///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
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

  /// Creates multiple signed URLs. Use a signed URL to share a file for a fixed amount of time.
  ///
  /// Each item in the returned array is a ``SignedURLResult``: either `.success(path:signedURL:)` or
  /// `.failure(path:error:)`. Exactly one case is guaranteed per item.
  /// - Parameters:
  ///   - paths: The file paths to be downloaded, including the current file names. For example `["folder/image.png", "folder2/image2.png"]`.
  ///   - expiresIn: The number of seconds until the signed URLs expire. For example, `60` for URLs which are valid for one minute.
  ///   - download: Trigger a download with the specified file name.
  ///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
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

  /// Creates multiple signed URLs. Use a signed URL to share a file for a fixed amount of time.
  ///
  /// Each item in the returned array is a ``SignedURLResult``: either `.success(path:signedURL:)` or
  /// `.failure(path:error:)`. Exactly one case is guaranteed per item.
  /// - Parameters:
  ///   - paths: The file paths to be downloaded, including the current file names. For example `["folder/image.png", "folder2/image2.png"]`.
  ///   - expiresIn: The number of seconds until the signed URLs expire. For example, `60` for URLs which are valid for one minute.
  ///   - download: Trigger a download with the default file name.
  ///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
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

  /// Deletes files within the same bucket
  /// - Parameters:
  ///   - paths: An array of files to be deletes, including the path and file name. For example [`folder/image.png`].
  /// - Returns: A list of removed ``FileObject``.
  @discardableResult
  public func remove(paths: [String]) async throws -> [FileObject] {
    try await client.fetchDecoded(
      .delete,
      "object/\(bucketId)",
      body: .data(client.encoder.encode(["prefixes": paths]))
    )
  }

  /// Lists all the files within a bucket.
  /// - Parameters:
  ///   - path: The folder path.
  ///   - options: Search options, including `limit`, `offset`, and `sortBy`.
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

  /// Downloads a file from a private bucket. For public buckets, make a request to the URL returned
  /// from ``StorageFileApi/getPublicURL(path:download:fileName:options:)`` instead.
  /// - Parameters:
  ///   - path: The file path to be downloaded, including the path and file name. For example `folder/image.png`.
  ///   - options: Transform the asset before serving it to the client.
  ///   - additionalQueryItems: Additional query items to be added to the request.
  ///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
  /// - Returns: The data of the downloaded file.
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

  /// Retrieves the details of an existing file.
  public func info(path: String) async throws -> FileObjectV2 {
    let _path = _getFinalPath(path)

    return try await client.fetchDecoded(.get, "object/info/\(_path)")
  }

  /// Checks the existence of file.
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

  /// A simple convenience function to get the URL for an asset in a public bucket. If you do not want to use this function, you can construct the public URL by concatenating the bucket URL with the path to the asset. This function does not verify if the bucket is public. If a public URL is created for a bucket which is not public, you will not be able to download the asset.
  /// - Parameters:
  ///  - path: The path and name of the file to generate the public URL for. For example `folder/image.png`.
  ///  - download: Trigger a download with the specified file name.
  ///  - options: Transform the asset before retrieving it on the client.
  ///  - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
  ///
  ///  - Note: The bucket needs to be set to public, either via ``StorageBucketApi/updateBucket(_:options:)`` or by going to Storage on [supabase.com/dashboard](https://supabase.com/dashboard), clicking the overflow menu on a bucket and choosing "Make public".
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

  /// A simple convenience function to get the URL for an asset in a public bucket. If you do not want to use this function, you can construct the public URL by concatenating the bucket URL with the path to the asset. This function does not verify if the bucket is public. If a public URL is created for a bucket which is not public, you will not be able to download the asset.
  /// - Parameters:
  ///  - path: The path and name of the file to generate the public URL for. For example `folder/image.png`.
  ///  - download: Trigger a download with the default file name.
  ///  - options: Transform the asset before retrieving it on the client.
  ///  - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
  ///
  ///  - Note: The bucket needs to be set to public, either via ``StorageBucketApi/updateBucket(_:options:)`` or by going to Storage on [supabase.com/dashboard](https://supabase.com/dashboard), clicking the overflow menu on a bucket and choosing "Make public".
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

  /// Creates a signed upload URL. Signed upload URLs can be used to upload files to the bucket without further authentication. They are valid for 2 hours.
  /// - Parameter path: The file path, including the current file name. For example `folder/image.png`.
  /// - Returns: A URL that can be used to upload files to the bucket without further
  /// authentication.
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

  /// Upload a file with a token generated from ``StorageFileApi/createSignedUploadURL(path:)``.
  /// - Parameters:
  ///   - path: The file path, including the file name. Should be of the format `folder/subfolder/filename.png`. The bucket must already exist before attempting to upload.
  ///   - token: The token generated from ``StorageFileApi/createSignedUploadURL(path:)``.
  ///   - data: The Data to be stored in the bucket.
  ///   - options: HTTP headers, for example `cacheControl`.
  /// - Returns: A key pointing to stored location.
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

  /// Upload a file with a token generated from ``StorageFileApi/createSignedUploadURL(path:)``.
  /// - Parameters:
  ///   - path: The file path, including the file name. Should be of the format `folder/subfolder/filename.png`. The bucket must already exist before attempting to upload.
  ///   - token: The token generated from ``StorageFileApi/createSignedUploadURL(path:)``.
  ///   - fileURL: The file URL to be stored in the bucket.
  ///   - options: HTTP headers, for example `cacheControl`.
  /// - Returns: A key pointing to stored location.
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
