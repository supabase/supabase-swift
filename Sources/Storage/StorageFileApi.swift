import Foundation
import Helpers
import class MultipartFormData.MultipartFormData

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let DEFAULT_SEARCH_OPTIONS = SearchOptions(
  limit: 100,
  offset: 0,
  sortBy: SortBy(
    column: "name",
    order: "asc"
  )
)

private let defaultFileOptions = FileOptions(
  cacheControl: "3600",
  contentType: "text/plain;charset=UTF-8",
  upsert: false
)

/// Supabase Storage File API
public class StorageFileApi: StorageApi, @unchecked Sendable {
  /// The bucket id to operate on.
  let bucketId: String

  init(bucketId: String, configuration: StorageClientConfiguration) {
    self.bucketId = bucketId
    super.init(configuration: configuration)
  }

  private struct MoveResponse: Decodable {
    let message: String
  }

  private struct SignedURLResponse: Decodable {
    let signedURL: URL
  }

  private func encodeMetadata(_ metadata: JSONObject) -> Data {
    let encoder = AnyJSON.encoder
    return (try? encoder.encode(metadata)) ?? "{}".data(using: .utf8)!
  }

  func uploadOrUpdate(
    method: HTTPMethod,
    path: String,
    formData: MultipartFormData,
    options: FileOptions?
  ) async throws -> FileUploadResponse {
    var headers = HTTPHeaders()

    let options = options ?? defaultFileOptions
    let metadata = options.metadata

    if method == .post {
      headers.update(name: "x-upsert", value: "\(options.upsert)")
    }

    headers["duplex"] = options.duplex

    if let metadata {
      formData.append(encodeMetadata(metadata), withName: "metadata")
    }

    formData.append(
      options.cacheControl.data(using: .utf8)!,
      withName: "cacheControl"
    )

    struct UploadResponse: Decodable {
      let Key: String
      let Id: String
    }

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/\(bucketId)/\(path)"),
        method: method,
        query: [],
        formData: formData,
        options: options,
        headers: headers
      )
    )
    .decoded(as: UploadResponse.self, decoder: configuration.decoder)

    return FileUploadResponse(
      id: response.Id,
      path: path,
      fullPath: response.Key
    )
  }

  /// Uploads a file to an existing bucket.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder/filename.png`. The
  /// bucket must already exist before attempting to upload.
  ///   - data: The Data to be stored in the bucket.
  ///   - options: HTTP headers. For example `cacheControl`
  @discardableResult
  public func upload(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    let fileName = path.fileName
    let formData = MultipartFormData()
    formData.append(
      data,
      withName: fileName,
      fileName: fileName,
      mimeType: options.contentType ?? mimeType(forPathExtension: path.pathExtension)
    )
    return try await uploadOrUpdate(method: .post, path: path, formData: formData, options: options)
  }

  @discardableResult
  public func upload(
    _ path: String,
    fileURL: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    let fileName = path.fileName
    let formData = MultipartFormData()
    formData.append(fileURL, withName: fileName, fileName: fileName)
    return try await uploadOrUpdate(method: .post, path: path, formData: formData, options: options)
  }

  /// Replaces an existing file at the specified path with a new one.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder`. The bucket
  /// already exist before attempting to upload.
  ///   - data: The Data to be stored in the bucket.
  ///   - options: HTTP headers. For example `cacheControl`
  @discardableResult
  public func update(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    let fileName = path.fileName
    let formData = MultipartFormData()
    formData.append(
      data,
      withName: fileName,
      fileName: fileName,
      mimeType: options.contentType ?? mimeType(forPathExtension: path.pathExtension)
    )
    return try await uploadOrUpdate(method: .put, path: path, formData: formData, options: options)
  }

  /// Replaces an existing file at the specified path with a new one.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder`. The bucket
  /// already exist before attempting to upload.
  ///   - fileURL: The file URL to be stored in the bucket.
  ///   - options: HTTP headers. For example `cacheControl`
  @discardableResult
  public func update(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    let formData = MultipartFormData()
    formData.append(fileURL, withName: path.fileName)
    return try await uploadOrUpdate(method: .put, path: path, formData: formData, options: options)
  }

  /// Moves an existing file, optionally renaming it at the same time.
  /// - Parameters:
  ///   - source: The original file path, including the current file name. For example `folder/image.png`.
  ///   - destination: The new file path, including the new file name. For example `folder/image-copy.png`.
  ///   - options: The destination options.
  public func move(
    from source: String,
    to destination: String,
    options: DestinationOptions? = nil
  ) async throws {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/move"),
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
  }

  /// Copies an existing file to a new path in the same bucket.
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

  /// Create signed url to download file without requiring permissions. This URL can be valid for a
  /// set number of seconds.
  /// - Parameters:
  ///   - path: The file path to be downloaded, including the current file name. For example
  /// `folder/image.png`.
  ///   - expiresIn: The number of seconds until the signed URL expires. For example, `60` for a URL
  /// which is valid for one minute.
  ///   - download: Trigger a download with the specified file name.
  ///   - transform: Transform the asset before serving it to the client.
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: String? = nil,
    transform: TransformOptions? = nil
  ) async throws -> URL {
    struct Body: Encodable {
      let expiresIn: Int
      let transform: TransformOptions?
    }

    let encoder = JSONEncoder()

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/sign/\(bucketId)/\(path)"),
        method: .post,
        body: encoder.encode(
          Body(expiresIn: expiresIn, transform: transform)
        )
      )
    )
    .decoded(as: SignedURLResponse.self, decoder: configuration.decoder)

    return try makeSignedURL(response.signedURL, download: download)
  }

  /// Create signed url to download file without requiring permissions. This URL can be valid for a
  /// set number of seconds.
  /// - Parameters:
  ///   - path: The file path to be downloaded, including the current file name. For example
  /// `folder/image.png`.
  ///   - expiresIn: The number of seconds until the signed URL expires. For example, `60` for a URL
  /// which is valid for one minute.
  ///   - download: Trigger a download with the default file name.
  ///   - transform: Transform the asset before serving it to the client.
  public func createSignedURL(
    path: String,
    expiresIn: Int,
    download: Bool,
    transform: TransformOptions? = nil
  ) async throws -> URL {
    try await createSignedURL(
      path: path,
      expiresIn: expiresIn,
      download: download ? "" : nil,
      transform: transform
    )
  }

  /// Creates multiple signed URLs. Use a signed URL to share a file for a fixed amount of time.
  /// - Parameters:
  ///   - paths: The file paths to be downloaded, including the current file names. For example
  /// `["folder/image.png", "folder2/image2.png"]`.
  ///   - expiresIn: The number of seconds until the signed URLs expire. For example, `60` for URLs
  /// which are valid for one minute.
  ///   - download: Trigger a download with the specified file name.
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: String? = nil
  ) async throws -> [URL] {
    struct Params: Encodable {
      let expiresIn: Int
      let paths: [String]
    }

    let encoder = JSONEncoder()

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/sign/\(bucketId)"),
        method: .post,
        body: encoder.encode(
          Params(expiresIn: expiresIn, paths: paths)
        )
      )
    )
    .decoded(as: [SignedURLResponse].self, decoder: configuration.decoder)

    return try response.map { try makeSignedURL($0.signedURL, download: download) }
  }

  /// Creates multiple signed URLs. Use a signed URL to share a file for a fixed amount of time.
  /// - Parameters:
  ///   - paths: The file paths to be downloaded, including the current file names. For example
  /// `["folder/image.png", "folder2/image2.png"]`.
  ///   - expiresIn: The number of seconds until the signed URLs expire. For example, `60` for URLs
  /// which are valid for one minute.
  ///   - download: Trigger a download with the default file name.
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: Bool
  ) async throws -> [URL] {
    try await createSignedURLs(paths: paths, expiresIn: expiresIn, download: download ? "" : nil)
  }

  private func makeSignedURL(_ signedURL: URL, download: String?) throws -> URL {
    guard
      let signedURLComponents = URLComponents(
        url: signedURL,
        resolvingAgainstBaseURL: false
      ),
      var baseURLComponents = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false)
    else {
      throw URLError(.badURL)
    }

    baseURLComponents.path += signedURLComponents.path
    baseURLComponents.queryItems = signedURLComponents.queryItems ?? []

    if let download {
      baseURLComponents.queryItems!.append(URLQueryItem(name: "download", value: download))
    }

    guard let signedURL = baseURLComponents.url else {
      throw URLError(.badURL)
    }

    return signedURL
  }

  /// Deletes files within the same bucket
  /// - Parameters:
  ///   - paths: An array of files to be deletes, including the path and file name. For example
  /// [`folder/image.png`].
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

  /// Lists all the files within a bucket.
  /// - Parameters:
  ///   - path: The folder path.
  ///   - options: Search options, including `limit`, `offset`, and `sortBy`.
  public func list(
    path: String? = nil,
    options: SearchOptions? = nil
  ) async throws -> [FileObject] {
    let encoder = JSONEncoder()

    var options = options ?? DEFAULT_SEARCH_OPTIONS
    options.prefix = path ?? ""

    return try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/list/\(bucketId)"),
        method: .post,
        body: encoder.encode(options)
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Downloads a file from a private bucket. For public buckets, make a request to the URL returned
  /// from ``StorageFileApi/getPublicURL(path:download:fileName:options:)`` instead.
  /// - Parameters:
  ///   - path: The file path to be downloaded, including the path and file name. For example
  /// `folder/image.png`.
  ///   - options: Transform the asset before serving it to the client.
  @discardableResult
  public func download(path: String, options: TransformOptions? = nil) async throws -> Data {
    let queryItems = options?.queryItems ?? []

    let renderPath = options != nil ? "render/image/authenticated" : "object"

    return try await execute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("\(renderPath)/\(bucketId)/\(path)"),
        method: .get,
        query: queryItems
      )
    )
    .data
  }

  /// Retrieves the details of an existing file.
  public func info(path: String) async throws -> FileObjectV2 {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/info/\(bucketId)/\(path)"),
        method: .get
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Checks the existence of file.
  public func exists(path: String) async throws -> Bool {
    do {
      try await execute(
        HTTPRequest(
          url: configuration.url.appendingPathComponent("object/\(bucketId)/\(path)"),
          method: .head
        )
      )
      return true
    } catch {
      var statusCode: Int?

      if let error = error as? StorageError {
        statusCode = error.statusCode.flatMap(Int.init)
      } else if let error = error as? HTTPError {
        statusCode = error.response.statusCode
      }

      if let statusCode, [400, 404].contains(statusCode) {
        return false
      }

      throw error
    }
  }

  /// Returns a public url for an asset.
  /// - Parameters:
  ///  - path: The file path to the asset. For example `folder/image.png`.
  ///  - download: Trigger a download with the specified file name.
  ///  - options: Transform the asset before retrieving it on the client.
  public func getPublicURL(
    path: String,
    download: String? = nil,
    options: TransformOptions? = nil
  ) throws -> URL {
    var queryItems: [URLQueryItem] = []

    guard var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: true)
    else {
      throw URLError(.badURL)
    }

    if let download {
      queryItems.append(URLQueryItem(name: "download", value: download))
    }

    if let optionsQueryItems = options?.queryItems {
      queryItems.append(contentsOf: optionsQueryItems)
    }

    let renderPath = options != nil ? "render/image" : "object"

    components.path += "/\(renderPath)/public/\(bucketId)/\(path)"
    components.queryItems = !queryItems.isEmpty ? queryItems : nil

    guard let generatedUrl = components.url else {
      throw URLError(.badURL)
    }

    return generatedUrl
  }

  /// Returns a public url for an asset.
  /// - Parameters:
  ///  - path: The file path to the asset. For example `folder/image.png`.
  ///  - download: Trigger a download with the default file name.
  ///  - options: Transform the asset before retrieving it on the client.
  public func getPublicURL(
    path: String,
    download: Bool,
    options: TransformOptions? = nil
  ) throws -> URL {
    try getPublicURL(path: path, download: download ? "" : nil, options: options)
  }

  /// Creates a signed upload URL.
  /// - Parameter path: The file path, including the current file name. For example
  /// `folder/image.png`.
  /// - Returns: A URL that can be used to upload files to the bucket without further
  /// authentication.
  ///
  /// - Note: Signed upload URLs can be used to upload files to the bucket without further
  /// authentication. They are valid for 2 hours.
  public func createSignedUploadURL(
    path: String,
    options: CreateSignedUploadURLOptions? = nil
  ) async throws -> SignedUploadURL {
    struct Response: Decodable {
      let url: URL
    }

    var headers = HTTPHeaders()
    if let upsert = options?.upsert, upsert {
      headers["x-upsert"] = "true"
    }

    let response = try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("object/upload/sign/\(bucketId)/\(path)"),
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
      throw StorageError(statusCode: nil, message: "No token returned by API", error: nil)
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
    let fileName = path.fileName
    let formData = MultipartFormData()
    formData.append(
      data,
      withName: fileName,
      fileName: fileName,
      mimeType: options?.contentType ?? mimeType(forPathExtension: path.pathExtension)
    )
    return try await _uploadToSignedURL(
      path: path,
      token: token,
      formData: formData,
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
    fileURL: Data,
    options: FileOptions? = nil
  ) async throws -> SignedURLUploadResponse {
    let formData = MultipartFormData()
    formData.append(fileURL, withName: path.fileName)
    return try await _uploadToSignedURL(
      path: path,
      token: token,
      formData: formData,
      options: options
    )
  }

  private func _uploadToSignedURL(
    path: String,
    token: String,
    formData: MultipartFormData,
    options: FileOptions?
  ) async throws -> SignedURLUploadResponse {
    let options = options ?? defaultFileOptions
    var headers = HTTPHeaders([
      "x-upsert": "\(options.upsert)",
    ])
    headers["duplex"] = options.duplex

    if let metadata = options.metadata {
      formData.append(encodeMetadata(metadata), withName: "metadata")
    }

    formData.append(options.cacheControl.data(using: .utf8)!, withName: "cacheControl")

    struct UploadResponse: Decodable {
      let Key: String
    }

    let fullPath = try await execute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("object/upload/sign/\(bucketId)/\(path)"),
        method: .put,
        query: [URLQueryItem(name: "token", value: token)],
        formData: formData,
        options: options,
        headers: headers
      )
    )
    .decoded(as: UploadResponse.self, decoder: configuration.decoder)
    .Key

    return SignedURLUploadResponse(path: path, fullPath: fullPath)
  }
}
