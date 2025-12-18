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
    UTType(filenameExtension: pathExtension)?.preferredMIMEType
      ?? "application/octet-stream"
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
  // NOTE:
  // `AnyJSON.encoder` is a shared instance and tests may mutate its configuration (e.g. enable
  // `.prettyPrinted`), which would make multipart bodies unstable and break snapshots.
  // Use a fresh encoder instead to keep metadata encoding deterministic and compact.
  let encoder = JSONEncoder.supabase()
  encoder.outputFormatting = [.sortedKeys]
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
