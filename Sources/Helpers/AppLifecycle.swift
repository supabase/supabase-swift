//
//  AppLifecycle.swift
//  Helpers
//
//  Created by Guilherme Souza on 06/11/26.
//

import ConcurrencyExtras
import Foundation

#if os(watchOS)
  import WatchKit
#elseif canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// An app lifecycle event. Each module maps these events to its own policy.
package enum AppLifecycleEvent: Hashable, Sendable {
  /// The app is in the foreground, or is about to enter it.
  case foreground
  /// The app is in the background, where the system may suspend it.
  case background
  /// The app became active. A return to the foreground posts it after `.foreground`, and a cold
  /// launch, Control Center, an alert, or a Mac app that gets focus posts it alone.
  case didBecomeActive
  /// The device was unlocked, so data protected until then can be read.
  case protectedDataDidBecomeAvailable
  /// The Mac is going to sleep.
  case systemWillSleep
  /// The Mac woke from sleep.
  case systemDidWake
}

/// The app lifecycle of the current platform, the one source for Auth and Realtime.
package struct AppLifecycle: Sendable {
  /// `true` where the system can run the app in the background: on iOS, tvOS, visionOS, Mac
  /// Catalyst, and watchOS. A Mac app and a Linux process stay in the foreground.
  package var hasBackgroundState: Bool

  /// Returns a new stream of the lifecycle. Each call observes the system on its own.
  ///
  /// The stream yields the current state, `.foreground` or `.background`, first. It then yields
  /// each event in the order the system posts it. Ending the stream removes its observers. Where
  /// there is no app lifecycle, the stream ends after the current state.
  package var events: @Sendable () async -> AsyncStream<AppLifecycleEvent>

  package init(
    hasBackgroundState: Bool,
    events: @escaping @Sendable () async -> AsyncStream<AppLifecycleEvent>
  ) {
    self.hasBackgroundState = hasBackgroundState
    self.events = events
  }
}

extension AppLifecycle {
  #if canImport(Darwin)
    package static let live = AppLifecycle(
      hasBackgroundState: hasBackgroundState,
      events: { await MainActor.run { observe(notifications, initialState: currentState) } }
    )
  #else
    /// Never touches the main actor: a server may never run it.
    package static let live = AppLifecycle(
      hasBackgroundState: false,
      events: { observe([], initialState: .foreground) }
    )
  #endif

  #if os(watchOS) || canImport(UIKit)
    private static let hasBackgroundState = true
  #else
    private static let hasBackgroundState = false
  #endif

  /// A Mac app that loses focus keeps running, so macOS has no background. It also reports the
  /// Mac going to sleep and waking, on the workspace center.
  @MainActor
  private static var notifications: [(NotificationCenter, Notification.Name, AppLifecycleEvent)] {
    #if os(watchOS)
      let center = NotificationCenter.default
      return [
        (center, WKApplication.willEnterForegroundNotification, .foreground),
        (center, WKApplication.didBecomeActiveNotification, .didBecomeActive),
        (center, WKApplication.didEnterBackgroundNotification, .background),
      ]
    #elseif canImport(UIKit)
      let center = NotificationCenter.default
      return [
        (center, UIApplication.willEnterForegroundNotification, .foreground),
        (center, UIApplication.didBecomeActiveNotification, .didBecomeActive),
        (center, UIApplication.didEnterBackgroundNotification, .background),
        (
          center, UIApplication.protectedDataDidBecomeAvailableNotification,
          .protectedDataDidBecomeAvailable
        ),
      ]
    #elseif canImport(AppKit)
      let workspace = NSWorkspace.shared.notificationCenter
      return [
        (NotificationCenter.default, NSApplication.didBecomeActiveNotification, .didBecomeActive),
        (workspace, NSWorkspace.willSleepNotification, .systemWillSleep),
        (workspace, NSWorkspace.didWakeNotification, .systemDidWake),
      ]
    #else
      return []
    #endif
  }

  #if canImport(UIKit) && !os(watchOS)
    /// An app extension has no shared `UIApplication`.
    package static var isAppExtension: Bool { Bundle.main.bundlePath.hasSuffix(".appex") }
  #endif

  @MainActor
  private static var currentState: AppLifecycleEvent {
    #if os(watchOS)
      WKApplication.shared().applicationState == .background ? .background : .foreground
    #elseif canImport(UIKit)
      guard !isAppExtension else { return .foreground }
      return UIApplication.shared.applicationState == .background ? .background : .foreground
    #else
      .foreground
    #endif
  }

  /// Yields `initialState`, then each event of `notifications` as its center posts it. With no
  /// notifications to observe, the stream ends after `initialState`.
  static func observe(
    _ notifications: [(NotificationCenter, Notification.Name, AppLifecycleEvent)],
    initialState: AppLifecycleEvent
  ) -> AsyncStream<AppLifecycleEvent> {
    let (events, continuation) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
    continuation.yield(initialState)
    guard !notifications.isEmpty else {
      continuation.finish()
      return events
    }

    let observers = UncheckedSendable(
      notifications.map { center, name, event in
        (
          center,
          center.addObserver(forName: name, object: nil, queue: nil) { _ in
            continuation.yield(event)
          }
        )
      }
    )
    continuation.onTermination = { _ in
      for (center, observer) in observers.value {
        center.removeObserver(observer)
      }
    }
    return events
  }
}
