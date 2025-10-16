//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 16/01/24.
//

import Alamofire
import Foundation

extension StorageClientConfiguration {
  @available(
    *,
    deprecated,
    message:
      "Replace usages of this initializer with new init(url:headers:encoder:decoder:alamofireSession:logger:useNewHostname:)"
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
      alamofireSession: .default,
      logger: nil,
      useNewHostname: false
    )
  }

  @available(
    *,
    deprecated,
    message:
      "Use init(url:headers:encoder:decoder:alamofireSession:logger:useNewHostname:) instead. This initializer will be removed in a future version."
  )
  @_disfavoredOverload
  public init(
    url: URL,
    headers: [String: String],
    encoder: JSONEncoder = .defaultStorageEncoder,
    decoder: JSONDecoder = .defaultStorageDecoder,
    session: StorageHTTPSession,
    logger: (any SupabaseLogger)? = nil,
    useNewHostname: Bool = false
  ) {
    self.init(
      url: url,
      headers: headers,
      encoder: encoder,
      decoder: decoder,
      session: session,
      alamofireSession: .default,
      logger: logger,
      useNewHostname: useNewHostname
    )
  }
}

extension StorageFileApi {
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
