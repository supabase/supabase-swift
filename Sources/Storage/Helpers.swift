//
//  Helpers.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

#if canImport(MobileCoreServices)
  import MobileCoreServices
#elseif canImport(CoreServices)
  import CoreServices
#endif

#if canImport(UniformTypeIdentifiers)
  import UniformTypeIdentifiers

  func mimeType(forPathExtension pathExtension: String) -> String {
    if #available(iOS 14, macOS 11, tvOS 14, watchOS 7, visionOS 1, *) {
      return UTType(filenameExtension: pathExtension)?.preferredMIMEType
        ?? "application/octet-stream"
    } else {
      if let id = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension, pathExtension as CFString, nil
      )?.takeRetainedValue(),
        let contentType = UTTypeCopyPreferredTagWithClass(id, kUTTagClassMIMEType)?
          .takeRetainedValue()
      {
        return contentType as String
      }

      return "application/octet-stream"
    }
  }
#else

  // MARK: - Private - Mime Type

  func mimeType(forPathExtension pathExtension: String) -> String {
    #if canImport(CoreServices) || canImport(MobileCoreServices)
      if let id = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension, pathExtension as CFString, nil
      )?.takeRetainedValue(),
        let contentType = UTTypeCopyPreferredTagWithClass(id, kUTTagClassMIMEType)?
          .takeRetainedValue()
      {
        return contentType as String
      }
    #endif

    return "application/octet-stream"
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
