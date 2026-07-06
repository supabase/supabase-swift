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

func encodeMetadata(_ metadata: JSONObject) -> Data {
  let encoder = AnyJSON.encoder
  return (try? encoder.encode(metadata)) ?? "{}".data(using: .utf8)!
}

extension String {
  var pathExtension: String {
    (self as NSString).pathExtension
  }

  var fileName: String {
    (self as NSString).lastPathComponent
  }
}
