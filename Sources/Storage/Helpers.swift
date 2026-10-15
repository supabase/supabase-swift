//
//  Helpers.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

#if canImport(UniformTypeIdentifiers)
  import UniformTypeIdentifiers

  func mimeType(forPathExtension pathExtension: String) -> String {
    UTType(filenameExtension: pathExtension)?.preferredMIMEType
      ?? "application/octet-stream"
  }
#else

  // MARK: - Private - Mime Type

  func mimeType(forPathExtension pathExtension: String) -> String {
    "application/octet-stream"
  }
#endif

/// The `x-metadata` header value: the user metadata as base64 JSON.
func encodeMetadata(_ metadata: JSONObject) throws -> String {
  try Data(encodeMetadataJSON(metadata).utf8).base64EncodedString()
}

/// The user metadata as a JSON string.
func encodeMetadataJSON(_ metadata: JSONObject) throws -> String {
  do {
    return String(decoding: try JSONEncoder.storage.encode(metadata), as: UTF8.self)
  } catch {
    throw StorageError(
      kind: .invalidRequest,
      message: "The upload metadata cannot be encoded as JSON.",
      underlyingError: error)
  }
}

extension String {
  var pathExtension: String {
    (self as NSString).pathExtension
  }

  var fileName: String {
    (self as NSString).lastPathComponent
  }
}
