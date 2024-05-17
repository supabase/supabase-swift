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

struct URLOpener {
  var open: @MainActor @Sendable (_ url: URL) -> Void
}

extension URLOpener {
  static var live: Self {
    URLOpener { url in
      #if os(macOS)
        NSWorkspace.shared.open(url)
      #elseif os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
        UIApplication.shared.open(url)
      #elseif os(watchOS)
        WKExtension.shared().openSystemURL(url)
      #endif
    }
  }
}
