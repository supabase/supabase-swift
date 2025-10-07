//
//  AvatarImage.swift
//  UserManagement
//
//  Created by Guilherme Souza on 17/11/23.
//

import SwiftUI

#if canImport(UIKit)
  typealias PlatformImage = UIImage
  extension Image {
    init(platformImage: PlatformImage) {
      self.init(uiImage: platformImage)
    }
  }

#elseif canImport(AppKit)
  typealias PlatformImage = NSImage
  extension Image {
    init(platformImage: PlatformImage) {
      self.init(nsImage: platformImage)
    }
  }
#endif

struct AvatarImage: Transferable, Equatable {
  let image: Image
  let data: Data

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(importedContentType: .image) { data in
      guard let image = await AvatarImage(data: data) else {
        throw TransferError.importFailed
      }

      return image
    }
  }
}

extension AvatarImage {
  init?(data: Data) async {
    guard let uiImage = PlatformImage(data: data) else {
      return nil
    }

    let image = await Image(platformImage: uiImage)
    self.init(image: image, data: data)
  }
}

enum TransferError: Error {
  case importFailed
}
