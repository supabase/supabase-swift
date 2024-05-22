//
//  Helpers.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

#if canImport(CoreServices)
  import CoreServices
#endif

#if canImport(UniformTypeIdentifiers)
  import UniformTypeIdentifiers
#endif

#if os(Linux) || os(Windows)
  /// On Linux or Windows this method always returns `application/octet-stream`.
  func mimeTypeForExtension(_: String) -> String {
    "application/octet-stream"
  }
#else
  func mimeTypeForExtension(_ fileExtension: String) -> String {
    if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, visionOS 1.0, *) {
      return UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
    } else {
      guard
        let type = UTTypeCreatePreferredIdentifierForTag(
          kUTTagClassFilenameExtension,
          fileExtension as NSString,
          nil
        )?.takeUnretainedValue(),
        let mimeType = UTTypeCopyPreferredTagWithClass(
          type,
          kUTTagClassMIMEType
        )?.takeUnretainedValue()
      else { return "application/octet-stream" }

      return mimeType as String
    }
  }
#endif

extension String {
  var pathExtension: String {
    (self as NSString).pathExtension
  }

  var fileName: String {
    (self as NSString).lastPathComponent
  }
}
