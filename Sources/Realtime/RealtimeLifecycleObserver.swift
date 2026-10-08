//
//  RealtimeLifecycleObserver.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
  import Foundation

  #if canImport(UIKit)
    import UIKit
  #else
    import AppKit
  #endif

  /// Wakes the engine when the app comes to the foreground, so a socket waiting out a reconnect
  /// backoff tries again at once. It never disconnects on background.
  final class RealtimeLifecycleObserver: @unchecked Sendable {
    // Written once in `init`, then only read.
    private let observers: [any NSObjectProtocol]

    init(engine: RealtimeEngine) {
      #if canImport(UIKit)
        let name = UIApplication.willEnterForegroundNotification
      #else
        let name = NSApplication.willBecomeActiveNotification
      #endif
      observers = [
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
          Task { await engine.wake() }
        }
      ]
    }

    deinit {
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
  }
#endif
