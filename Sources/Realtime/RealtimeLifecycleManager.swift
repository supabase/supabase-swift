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
  /// On backgrounding, the manager tells the client to record whether the socket was connected.
  /// On foregrounding, it forwards the event to ``RealtimeClientV2/handleAppForeground()``,
  /// which reconnects and re-joins channels only if the socket was connected before the app
  /// backgrounded and has since been torn down. The manager does not proactively disconnect
  /// on backgrounding — connections often survive short background cycles, and tearing them
  /// down preemptively wastes work during rapid transitions.
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
        let backgroundName = UIApplication.didEnterBackgroundNotification
      #elseif canImport(AppKit)
        let foregroundName = NSApplication.willBecomeActiveNotification
        let backgroundName = NSApplication.didResignActiveNotification
      #endif

      let foregroundObserver = center.addObserver(
        forName: foregroundName,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.handleForeground()
      }

      let backgroundObserver = center.addObserver(
        forName: backgroundName,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.handleBackground()
      }

      lock.lock()
      observers.append(foregroundObserver)
      observers.append(backgroundObserver)
      lock.unlock()
    }

    private func handleForeground() {
      guard let client else { return }
      Task { await client.handleAppForeground() }
    }

    private func handleBackground() {
      guard let client else { return }
      client.handleAppBackground()
    }
  }

#endif
