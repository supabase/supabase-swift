import Foundation
@_spi(Internal) import _Helpers

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

/// Supabase Storage File API
public class StorageFileApi: StorageApi {
  /// The bucket id to operate on.
  var bucketId: String

  init(bucketId: String, configuration: StorageClientConfiguration) {
    self.bucketId = bucketId
    super.init(configuration: configuration)
  }

  struct UploadResponse: Decodable {
    let Key: String
  }

  func uploadOrUpdate(
    method: String,
    path: String,
    file: Data,
    fileOptions: FileOptions
  ) async throws -> String {
    let contentType = fileOptions.contentType
    var headers = [
      "x-upsert": "\(fileOptions.upsert)"
    ]

    headers["duplex"] = fileOptions.duplex

    let fileName = fileName(fromPath: path)

    let form = FormData()
    form.append(
      file: File(name: fileName, data: file, fileName: fileName, contentType: contentType)
    )

    return try await execute(
      Request(
        path: "/object/\(bucketId)/\(path)",
        method: method,
        formData: form,
        options: fileOptions,
        headers: headers
      )
    )
    .decoded(as: UploadResponse.self, decoder: configuration.decoder).Key
  }

  /// Uploads a file to an existing bucket.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder/filename.png`. The
  /// bucket must already exist before attempting to upload.
  ///   - file: The File object to be stored in the bucket.
  ///   - fileOptions: HTTP headers. For example `cacheControl`
  @discardableResult
  public func upload(path: String, file: File, fileOptions: FileOptions = FileOptions())
    async throws -> String
  {
    try await uploadOrUpdate(method: "POST", path: path, file: file.data, fileOptions: fileOptions)
  }

  /// Replaces an existing file at the specified path with a new one.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder`. The bucket
  /// already exist before attempting to upload.
  ///   - file: The file object to be stored in the bucket.
  ///   - fileOptions: HTTP headers. For example `cacheControl`
  public func update(path: String, file: File, fileOptions: FileOptions = FileOptions())
    async throws -> String
  {
    try await uploadOrUpdate(method: "PUT", path: path, file: file.data, fileOptions: fileOptions)
  }

  /// Moves an existing file, optionally renaming it at the same time.
  /// - Parameters:
  ///   - fromPath: The original file path, including the current file name. For example
  /// `folder/image.png`.
  ///   - toPath: The new file path, including the new file name. For example
  /// `folder/image-copy.png`.
  public func move(fromPath: String, toPath: String) async throws -> [String: AnyJSON] {
    try await execute(
      Request(
        path: "/object/move",
        method: "POST",
        body: configuration.encoder.encode(
          [
            "bucketId": bucketId,
            "sourceKey": fromPath,
            "destinationKey": toPath,
          ]
        )
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Create signed url to download file without requiring permissions. This URL can be valid for a
  /// set number of seconds.
  /// - Parameters:
  ///   - path: The file path to be downloaded, including the current file name. For example
  /// `folder/image.png`.
  ///   - expiresIn: The number of seconds until the signed URL expires. For example, `60` for a URL
  /// which is valid for one minute.
  public func createSignedURL(path: String, expiresIn: Int) async throws -> SignedURL {
    try await execute(
      Request(
        path: "/object/sign/\(bucketId)/\(path)",
        method: "POST",
        body: configuration.encoder.encode(["expiresIn": expiresIn])
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Deletes files within the same bucket
  /// - Parameters:
  ///   - paths: An array of files to be deletes, including the path and file name. For example
  /// [`folder/image.png`].
  public func remove(paths: [String]) async throws -> [FileObject] {
    try await execute(
      Request(
        path: "/object/\(bucketId)",
        method: "DELETE",
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
    try await execute(
      Request(
        path: "/object/list/\(bucketId)",
        method: "POST",
        body: configuration.encoder.encode(options ?? DEFAULT_SEARCH_OPTIONS))
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Downloads a file.
  /// - Parameters:
  ///   - path: The file path to be downloaded, including the path and file name. For example
  /// `folder/image.png`.
  @discardableResult
  public func download(path: String) async throws -> Data {
    // TODO: implement missing functionality from https://github.com/supabase/storage-js/blob/main/src/packages/StorageFileApi.ts#L466
    try await execute(
      Request(path: "/object/\(bucketId)/\(path)", method: "GET")
    )
    .data
  }

  /// Returns a public url for an asset.
  /// - Parameters:
  ///  - path: The file path to the asset. For example `folder/image.png`.
  ///  - download: Whether the asset should be downloaded.
  ///  - fileName: If specified, the file name for the asset that is downloaded.
  ///  - options: Transform the asset before retrieving it on the client.
  public func getPublicURL(
    path: String,
    download: Bool = false,
    fileName: String = "",
    options: TransformOptions? = nil
  ) throws -> URL {
    var queryItems: [URLQueryItem] = []

    guard var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: true)
    else {
      throw URLError(.badURL)
    }

    if download {
      queryItems.append(URLQueryItem(name: "download", value: fileName))
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
}

private func fileName(fromPath path: String) -> String {
  (path as NSString).lastPathComponent
}
