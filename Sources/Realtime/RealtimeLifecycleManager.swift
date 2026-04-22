//
//  RealtimeLifecycleManager.swift
//  Realtime
//
//  Created by Guilherme Souza on 22/04/26.
//

import ConcurrencyExtras
import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)

  /// Observes platform app lifecycle notifications and nudges the Realtime client to recover
  /// its connection when the app returns to the foreground.
  ///
  /// On foregrounding, the manager forwards the event to
  /// ``RealtimeClientV2/setAppStateActive(_:)``, which reconnects and re-joins existing channels
  /// only if the WebSocket was actually closed while the app was in the background. The manager
  /// does not react to backgrounding — connections often survive short background cycles, and
  /// tearing them down preemptively wastes work during rapid transitions.
  final class RealtimeLifecycleManager: @unchecked Sendable {
    private weak var client: RealtimeClientV2?
    private var observers: [any NSObjectProtocol] = []
    private let lock = NSLock()

    init(client: RealtimeClientV2) {
      self.client = client
      setupObservers()
    }

    deinit {
      let center = NotificationCenter.default
      for observer in observers {
        center.removeObserver(observer)
      }
    }

    private func setupObservers() {
      let center = NotificationCenter.default

      #if canImport(UIKit)
        let foregroundName = UIApplication.willEnterForegroundNotification
      #elseif canImport(AppKit)
        let foregroundName = NSApplication.willBecomeActiveNotification
      #endif

      let foregroundObserver = center.addObserver(
        forName: foregroundName,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.handleForeground()
      }

      lock.lock()
      observers.append(foregroundObserver)
      lock.unlock()
    }

    private func handleForeground() {
      guard let client else { return }
      Task { await client.setAppStateActive(true) }
    }
  }

#endif
