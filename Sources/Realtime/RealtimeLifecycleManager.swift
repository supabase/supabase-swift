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

  /// Observes platform app lifecycle notifications and drives the Realtime client's connection
  /// state accordingly.
  ///
  /// When the app enters the background, any pending reconnect is cancelled and the client is
  /// disconnected to release resources. When the app returns to the foreground, the client is
  /// reconnected and any existing channels are resubscribed.
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
        let backgroundName = UIApplication.didEnterBackgroundNotification
        let foregroundName = UIApplication.willEnterForegroundNotification
      #elseif canImport(AppKit)
        let backgroundName = NSApplication.willResignActiveNotification
        let foregroundName = NSApplication.willBecomeActiveNotification
      #endif

      let backgroundObserver = center.addObserver(
        forName: backgroundName,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.handleBackground()
      }

      let foregroundObserver = center.addObserver(
        forName: foregroundName,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.handleForeground()
      }

      lock.lock()
      observers.append(backgroundObserver)
      observers.append(foregroundObserver)
      lock.unlock()
    }

    private func handleBackground() {
      guard let client else { return }
      Task { await client.setAppStateActive(false) }
    }

    private func handleForeground() {
      guard let client else { return }
      Task { await client.setAppStateActive(true) }
    }
  }

#endif
