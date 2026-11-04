//
//  RealtimeLifecycleManager.swift
//  Realtime
//
//  Created by Guilherme Souza on 22/04/26.
//

import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)

  /// Observes platform app lifecycle notifications and hands them to the Realtime client, which
  /// recovers its connection when the app returns to the foreground.
  ///
  /// On backgrounding, the client records whether the socket was connected. On foregrounding,
  /// it reconnects and re-joins channels only if the socket was connected before the app
  /// backgrounded and has since been torn down. The client does not proactively disconnect
  /// on backgrounding — connections often survive short background cycles, and tearing them
  /// down preemptively wastes work during rapid transitions.
  ///
  /// The client owns the manager, so it is not `Sendable`. Its observers are fixed at init and
  /// only yield ``Input/appBackground`` and ``Input/appForeground`` into the client's inbox. It
  /// removes them in its own `deinit`.
  final class RealtimeLifecycleManager {
    private let observers: [any NSObjectProtocol]

    init(inbox: AsyncStream<Input>.Continuation) {
      let center = NotificationCenter.default

      #if canImport(UIKit)
        let foregroundName = UIApplication.willEnterForegroundNotification
        let backgroundName = UIApplication.didEnterBackgroundNotification
      #elseif canImport(AppKit)
        let foregroundName = NSApplication.willBecomeActiveNotification
        let backgroundName = NSApplication.didResignActiveNotification
      #endif

      observers = [
        center.addObserver(forName: foregroundName, object: nil, queue: nil) { _ in
          inbox.yield(.appForeground)
        },
        center.addObserver(forName: backgroundName, object: nil, queue: nil) { _ in
          inbox.yield(.appBackground)
        },
      ]
    }

    deinit {
      let center = NotificationCenter.default
      for observer in observers {
        center.removeObserver(observer)
      }
    }
  }

#endif
