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
    message: "Replace usages of this initializer with new init(url:headers:encoder:decoder:session:logger)"
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
}
