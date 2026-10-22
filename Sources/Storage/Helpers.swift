//
//  Helpers.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

#if canImport(UniformTypeIdentifiers)
  import UniformTypeIdentifiers
#endif

/// The upload `Content-Type` for a file extension: `UTType` where it exists, then
/// ``commonMIMETypes``, then `application/octet-stream`.
func mimeType(forPathExtension pathExtension: String) -> String {
  #if canImport(UniformTypeIdentifiers)
    if let mimeType = UTType(filenameExtension: pathExtension)?.preferredMIMEType {
      return mimeType
    }
  #endif
  return commonMIMETypes[pathExtension.lowercased()] ?? "application/octet-stream"
}

/// Linux and Android have no `UTType`, so without this table every upload there is stored as
/// `application/octet-stream`.
let commonMIMETypes: [String: String] = [
  "avif": "image/avif",
  "css": "text/css",
  "csv": "text/csv",
  "gif": "image/gif",
  "heic": "image/heic",
  "html": "text/html",
  "jpeg": "image/jpeg",
  "jpg": "image/jpeg",
  "js": "text/javascript",
  "json": "application/json",
  "md": "text/markdown",
  "mov": "video/quicktime",
  "mp3": "audio/mpeg",
  "mp4": "video/mp4",
  "pdf": "application/pdf",
  "png": "image/png",
  "svg": "image/svg+xml",
  "txt": "text/plain",
  "wav": "audio/wav",
  "webp": "image/webp",
  "zip": "application/zip",
]

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
