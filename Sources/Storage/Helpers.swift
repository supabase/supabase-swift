//
//  Helpers.swift
//
//
//  Created by Guilherme Souza on 22/05/24.
//

import CoreServices
import Foundation
import UniformTypeIdentifiers

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

extension String {
  var pathExtension: String {
    (self as NSString).pathExtension
  }

  var fileName: String {
    (self as NSString).lastPathComponent
  }
}
