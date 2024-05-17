//
//  URLOpener.swift
//
//
//  Created by Guilherme Souza on 17/05/24.
//

import Foundation

#if canImport(WatchKit)
  import WatchKit
#endif

#if canImport(UIKit)
  import UIKit
#endif

#if canImport(AppKit)
  import AppKit
#endif

enum URLOpener {
  @MainActor
  static func open(_ url: URL) {
    #if os(macOS)
      NSWorkspace.shared.open(url)
    #elseif os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
      UIApplication.shared.open(url)
    #elseif os(watchOS)
      WKExtension.shared().openSystemURL(url)
    #endif
  }
}
