//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 16/01/24.
//

import Foundation

extension StorageClientConfiguration {
  @available(
    *,
    deprecated,
    message:
      "Replace usages of this initializer with new init(url:headers:encoder:decoder:session:logger)"
  )
  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder = .defaultStorageEncoder,
    decoder: JSONDecoder = .defaultStorageDecoder,
    session: StorageHTTPSession = .init()
  ) {
    self.init(
      url: url,
      headers: headers,
      encoder: encoder,
      decoder: decoder,
      session: session,
      logger: nil
    )
  }
}

extension StorageFileApi {
  @available(
    *, deprecated,
    message: "Use download: DownloadBehavior? instead. Pass .withOriginalName to trigger download."
  )
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
      download: download ? DownloadBehavior.withOriginalName : nil,
      transform: transform,
      cacheNonce: cacheNonce
    )
  }

  @available(*, deprecated, message: "Use download: DownloadBehavior? instead.")
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: Bool,
    cacheNonce: String? = nil
  ) async throws -> [SignedURLResult] {
    try await createSignedURLs(
      paths: paths,
      expiresIn: expiresIn,
      download: download ? DownloadBehavior.withOriginalName : nil,
      cacheNonce: cacheNonce
    )
  }

  @available(*, deprecated, message: "Use download: DownloadBehavior? instead.")
  public func getPublicURL(
    path: String,
    download: Bool,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
  ) throws -> URL {
    try getPublicURL(
      path: path,
      download: download ? DownloadBehavior.withOriginalName : nil,
      options: options,
      cacheNonce: cacheNonce
    )
  }

  @_disfavoredOverload
  @available(
    *,
    deprecated,
    message:
      "Use createSignedURLs(paths:expiresIn:download:) that returns [SignedURLResult] to handle paths that do not exist."
  )
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: String? = nil
  ) async throws -> [URL] {
    let results: [SignedURLResult] = try await createSignedURLs(
      paths: paths, expiresIn: expiresIn, download: download)
    return results.compactMap(\.signedURL)
  }

  @_disfavoredOverload
  @available(
    *,
    deprecated,
    message:
      "Use createSignedURLs(paths:expiresIn:download:) that returns [SignedURLResult] to handle paths that do not exist."
  )
  public func createSignedURLs(
    paths: [String],
    expiresIn: Int,
    download: Bool
  ) async throws -> [URL] {
    try await createSignedURLs(paths: paths, expiresIn: expiresIn, download: download ? "" : nil)
  }

  @_disfavoredOverload
  @available(*, deprecated, message: "Please use method that returns FileUploadResponse.")
  @discardableResult
  public func upload(
    path: String,
    file: Data,
    options: FileOptions = FileOptions()
  ) async throws -> String {
    try await upload(path: path, file: file, options: options).fullPath
  }

  @_disfavoredOverload
  @available(*, deprecated, message: "Please use method that returns FileUploadResponse.")
  @discardableResult
  public func update(
    path: String,
    file: Data,
    options: FileOptions = FileOptions()
  ) async throws -> String {
    try await update(path: path, file: file, options: options).fullPath
  }

  @_disfavoredOverload
  @available(*, deprecated, message: "Please use method that returns FileUploadResponse.")
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    file: Data,
    options: FileOptions = FileOptions()
  ) async throws -> String {
    try await uploadToSignedURL(path: path, token: token, file: file, options: options).fullPath
  }

  @available(*, deprecated, renamed: "upload(_:data:options:)")
  @discardableResult
  public func upload(
    path: String,
    file: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await upload(path, data: file, options: options)
  }

  @available(*, deprecated, renamed: "update(_:data:options:)")
  @discardableResult
  public func update(
    path: String,
    file: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadResponse {
    try await update(path, data: file, options: options)
  }

  @available(*, deprecated, renamed: "updateToSignedURL(_:token:data:options:)")
  @discardableResult
  public func uploadToSignedURL(
    path: String,
    token: String,
    file: Data,
    options: FileOptions = FileOptions()
  ) async throws -> SignedURLUploadResponse {
    try await uploadToSignedURL(path, token: token, data: file, options: options)
  }
}

@available(
  *,
  deprecated,
  message:
    "File was deprecated and it isn't used in the package anymore, if you're using it on your application, consider replacing it as it will be removed on the next major release."
)
public struct File: Hashable, Equatable {
  public var name: String
  public var data: Data
  public var fileName: String?
  public var contentType: String?

  public init(name: String, data: Data, fileName: String?, contentType: String?) {
    self.name = name
    self.data = data
    self.fileName = fileName
    self.contentType = contentType
  }
}

@available(
  *,
  deprecated,
  renamed: "MultipartFormData",
  message:
    "FormData was deprecated in favor of MultipartFormData, and it isn't used in the package anymore, if you're using it on your application, consider replacing it as it will be removed on the next major release."
)
public class FormData {
  var files: [File] = []
  var boundary: String

  public init(boundary: String = UUID().uuidString) {
    self.boundary = boundary
  }

  public func append(file: File) {
    files.append(file)
  }

  public var contentType: String {
    "multipart/form-data; boundary=\(boundary)"
  }

  public var data: Data {
    var data = Data()

    for file in files {
      data.append("--\(boundary)\r\n")
      data.append("Content-Disposition: form-data; name=\"\(file.name)\"")
      if let filename = file.fileName?.replacingOccurrences(of: "\"", with: "_") {
        data.append("; filename=\"\(filename)\"")
      }
      data.append("\r\n")
      if let contentType = file.contentType {
        data.append("Content-Type: \(contentType)\r\n")
      }
      data.append("\r\n")
      data.append(file.data)
      data.append("\r\n")
    }

    data.append("--\(boundary)--\r\n")
    return data
  }
}

extension Data {
  mutating func append(_ string: String) {
    let data = string.data(
      using: String.Encoding.utf8,
      allowLossyConversion: true
    )
    append(data!)
  }
}

extension BucketOptions {
  @available(*, deprecated, renamed: "isPublic")
  public var `public`: Bool {
    get { isPublic }
    set { isPublic = newValue }
  }

  @_disfavoredOverload
  @available(*, deprecated, renamed: "init(isPublic:fileSizeLimit:allowedMimeTypes:)")
  public init(
    public isPublic: Bool = false,
    fileSizeLimit: String? = nil,
    allowedMimeTypes: [String]? = nil
  ) {
    self.init(
      isPublic: isPublic,
      fileSizeLimit: fileSizeLimit.map { StorageByteCount(stringLiteral: $0) },
      allowedMimeTypes: allowedMimeTypes
    )
  }

  @_disfavoredOverload
  @available(
    *, deprecated,
    message: "Use `init(isPublic:fileSizeLimit:allowedMimeTypes:)` with StorageByteCount instead."
  )
  public init(
    isPublic: Bool = false,
    fileSizeLimit: String? = nil,
    allowedMimeTypes: [String]? = nil
  ) {
    self.isPublic = isPublic
    self.fileSizeLimit = fileSizeLimit
    self.allowedMimeTypes = allowedMimeTypes
  }

}

extension SortBy {
  @available(*, deprecated, message: "Use `init` with `SortOrder` instead.")
  public init(column: String? = nil, order: String? = nil) {
    self.column = column
    self.order = order
  }
}

extension TransformOptions {
  @_disfavoredOverload
  @available(
    *, deprecated,
    message:
      "Use `init(width:height:resize:quality:format:)` with ResizeMode and ImageFormat instead."
  )
  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: String? = nil,
    quality: Int? = nil,
    format: String? = nil
  ) {
    self.width = width
    self.height = height
    self.resize = resize
    self.quality = quality
    self.format = format
  }
}
