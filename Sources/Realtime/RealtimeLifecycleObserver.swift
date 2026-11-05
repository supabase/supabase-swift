//
//  RealtimeLifecycleObserver.swift
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
  /// The signals are the app's background and foreground notifications on iOS, tvOS, and
  /// visionOS. On macOS an app that loses focus keeps its connection, so they are the Mac going
  /// to sleep and waking. What the client does with them is described at
  /// ``RealtimeClientOptions/handleAppLifecycle``.
  ///
  /// The client owns the observer, so it is not `Sendable`. Its observers are fixed at init and
  /// only yield ``Input/appBackground`` and ``Input/appForeground`` into the client's inbox. It
  /// removes them in its own `deinit`.
  final class RealtimeLifecycleObserver {
    private let center: NotificationCenter
    private let observers: [any NSObjectProtocol]

    init(inbox: AsyncStream<Input>.Continuation) {
      #if canImport(UIKit)
        center = NotificationCenter.default
        let foregroundName = UIApplication.willEnterForegroundNotification
        let backgroundName = UIApplication.didEnterBackgroundNotification
      #elseif canImport(AppKit)
        center = NSWorkspace.shared.notificationCenter
        let foregroundName = NSWorkspace.didWakeNotification
        let backgroundName = NSWorkspace.willSleepNotification
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
      for observer in observers {
        center.removeObserver(observer)
      }
    }
  }

#endif
