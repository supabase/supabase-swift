import Foundation

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

  /// StorageFileApi initializer
  /// - Parameters:
  ///   - url: Storage HTTP URL
  ///   - headers: HTTP headers.
  ///   - bucketId: The bucket id to operate on.
  init(url: String, headers: [String: String], bucketId: String, session: StorageHTTPSession) {
    self.bucketId = bucketId
    super.init(url: url, headers: headers, session: session)
  }

  /// Uploads a file to an existing bucket.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder/filename.png`. The
  /// bucket must already exist before attempting to upload.
  ///   - file: The File object to be stored in the bucket.
  ///   - fileOptions: HTTP headers. For example `cacheControl`
  public func upload(path: String, file: File, fileOptions: FileOptions?) async throws -> Any {
    guard let url = URL(string: "\(url)/object/\(bucketId)/\(path)") else {
      throw StorageError(message: "badURL")
    }

    let formData = FormData()
    formData.append(file: file)

    return try await fetch(
      url: url,
      method: .post,
      formData: formData,
      headers: headers,
      fileOptions: fileOptions
    )
  }

  /// Replaces an existing file at the specified path with a new one.
  /// - Parameters:
  ///   - path: The relative file path. Should be of the format `folder/subfolder`. The bucket
  /// already exist before attempting to upload.
  ///   - file: The file object to be stored in the bucket.
  ///   - fileOptions: HTTP headers. For example `cacheControl`
  public func update(path: String, file: File, fileOptions: FileOptions?) async throws -> Any {
    guard let url = URL(string: "\(url)/object/\(bucketId)/\(path)") else {
      throw StorageError(message: "badURL")
    }

    let formData = FormData()
    formData.append(file: file)

    return try await fetch(
      url: url,
      method: .put,
      formData: formData,
      headers: headers,
      fileOptions: fileOptions
    )
  }

  /// Moves an existing file, optionally renaming it at the same time.
  /// - Parameters:
  ///   - fromPath: The original file path, including the current file name. For example
  /// `folder/image.png`.
  ///   - toPath: The new file path, including the new file name. For example
  /// `folder/image-copy.png`.
  public func move(fromPath: String, toPath: String) async throws -> [String: Any] {
    guard let url = URL(string: "\(url)/object/move") else {
      throw StorageError(message: "badURL")
    }

    let response = try await fetch(
      url: url, method: .post,
      parameters: ["bucketId": bucketId, "sourceKey": fromPath, "destinationKey": toPath],
      headers: headers
    )

    guard let dict = response as? [String: Any] else {
      throw StorageError(message: "failed to parse response")
    }

    return dict
  }

  /// Create signed url to download file without requiring permissions. This URL can be valid for a
  /// set number of seconds.
  /// - Parameters:
  ///   - path: The file path to be downloaded, including the current file name. For example
  /// `folder/image.png`.
  ///   - expiresIn: The number of seconds until the signed URL expires. For example, `60` for a URL
  /// which is valid for one minute.
  public func createSignedURL(path: String, expiresIn: Int) async throws -> URL {
    guard let url = URL(string: "\(url)/object/sign/\(bucketId)/\(path)") else {
      throw StorageError(message: "badURL")
    }

    let response = try await fetch(
      url: url,
      method: .post,
      parameters: ["expiresIn": expiresIn],
      headers: headers
    )
    guard
      let dict = response as? [String: Any],
      let signedURLString = dict["signedURL"] as? String,
      let signedURL = URL(string: self.url.appending(signedURLString))
    else {
      throw StorageError(message: "failed to parse response")
    }
    return signedURL
  }

  /// Deletes files within the same bucket
  /// - Parameters:
  ///   - paths: An array of files to be deletes, including the path and file name. For example
  /// [`folder/image.png`].
  public func remove(paths: [String]) async throws -> [FileObject] {
    guard let url = URL(string: "\(url)/object/\(bucketId)") else {
      throw StorageError(message: "badURL")
    }

    let response = try await fetch(
      url: url,
      method: .delete,
      parameters: ["prefixes": paths],
      headers: headers
    )
    guard let array = response as? [[String: Any]] else {
      throw StorageError(message: "failed to parse response")
    }

    return array.compactMap { FileObject(from: $0) }
  }

  /// Lists all the files within a bucket.
  /// - Parameters:
  ///   - path: The folder path.
  ///   - options: Search options, including `limit`, `offset`, and `sortBy`.
  public func list(
    path: String? = nil,
    options: SearchOptions? = nil
  ) async throws -> [FileObject] {
    guard let url = URL(string: "\(url)/object/list/\(bucketId)") else {
      throw StorageError(message: "badURL")
    }

    var parameters: [String: Any] = ["prefix": path ?? ""]
    parameters["limit"] = options?.limit ?? DEFAULT_SEARCH_OPTIONS.limit
    parameters["offset"] = options?.offset ?? DEFAULT_SEARCH_OPTIONS.offset
    parameters["search"] = options?.search ?? DEFAULT_SEARCH_OPTIONS.search

    if let sortBy = options?.sortBy ?? DEFAULT_SEARCH_OPTIONS.sortBy {
      parameters["sortBy"] = [
        "column": sortBy.column,
        "order": sortBy.order,
      ]
    }

    let response = try await fetch(
      url: url, method: .post, parameters: parameters, headers: headers)

    guard let array = response as? [[String: Any]] else {
      throw StorageError(message: "failed to parse response")
    }

    return array.compactMap { FileObject(from: $0) }
  }

  /// Downloads a file.
  /// - Parameters:
  ///   - path: The file path to be downloaded, including the path and file name. For example
  /// `folder/image.png`.
  @discardableResult
  public func download(path: String) async throws -> Data {
    guard let url = URL(string: "\(url)/object/\(bucketId)/\(path)") else {
      throw StorageError(message: "badURL")
    }

    let response = try await fetch(url: url, parameters: nil)
    guard let data = response as? Data else {
      throw StorageError(message: "failed to parse response")
    }
    return data
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

    guard var components = URLComponents(string: url) else {
      throw StorageError(message: "badURL")
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
      throw StorageError(message: "badUrl")
    }

    return generatedUrl
  }

  @available(*, deprecated, renamed: "getPublicURL")
  public func getPublicUrl(
    path: String,
    download: Bool = false,
    fileName: String = "",
    options: TransformOptions? = nil
  ) throws -> URL {
    try getPublicURL(path: path, download: download, fileName: fileName, options: options)
  }
}
