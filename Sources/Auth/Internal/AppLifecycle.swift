//
//  AppLifecycle.swift
//  Auth
//
//

import Foundation

#if canImport(UIKit)
  import UIKit
#endif

#if canImport(WatchKit)
  import WatchKit
#endif

#if canImport(AppKit)
  import AppKit
#endif

#if canImport(ObjectiveC)
  /// Provides cross-platform app lifecycle notification names.
  enum AppLifecycle {
    /// Notification posted when the app becomes active (foreground).
    static var didBecomeActiveNotification: NSNotification.Name? {
      #if canImport(UIKit)
        #if canImport(WatchKit)
          if #available(watchOS 7.0, *) {
            return WKExtension.applicationDidBecomeActiveNotification
          }
          return nil
        #else
          return UIApplication.didBecomeActiveNotification
        #endif
      #elseif canImport(AppKit)
        return NSApplication.didBecomeActiveNotification
      #else
        return nil
      #endif
    }

    /// Notification posted when the app is about to resign active state.
    static var willResignActiveNotification: NSNotification.Name? {
      #if canImport(UIKit)
        #if canImport(WatchKit)
          if #available(watchOS 7.0, *) {
            return WKExtension.applicationWillResignActiveNotification
          }
          return nil
        #else
          return UIApplication.willResignActiveNotification
        #endif
      #elseif canImport(AppKit)
        return NSApplication.willResignActiveNotification
      #else
        return nil
      #endif
    }

    /// Notification posted when the app enters the background.
    static var didEnterBackgroundNotification: NSNotification.Name? {
      #if canImport(UIKit) && !os(watchOS)
        return UIApplication.didEnterBackgroundNotification
      #elseif canImport(AppKit)
        // macOS doesn't have a direct equivalent, use willResignActive instead
        return NSApplication.willResignActiveNotification
      #else
        return nil
      #endif
    }

    /// Notification posted when the app is about to enter the foreground.
    static var willEnterForegroundNotification: NSNotification.Name? {
      #if canImport(UIKit) && !os(watchOS)
        return UIApplication.willEnterForegroundNotification
      #elseif canImport(AppKit)
        // macOS doesn't have a direct equivalent, use didBecomeActive instead
        return NSApplication.didBecomeActiveNotification
      #else
        return nil
      #endif
    }

    /// Observes app background/foreground transitions using NotificationCenter.
    ///
    /// This method uses `addObserver(forName:object:queue:using:)` which is appropriate
    /// for long-lived subscriptions that don't need cancellation.
    ///
    /// - Parameters:
    ///   - onEnterBackground: Called when the app enters the background.
    ///   - onEnterForeground: Called when the app enters the foreground.
    @MainActor
    static func observeBackgroundTransitions(
      onEnterBackground: (@Sendable () -> Void)? = nil,
      onEnterForeground: (@Sendable () -> Void)? = nil
    ) {
      if let notification = didEnterBackgroundNotification, let handler = onEnterBackground {
        NotificationCenter.default.addObserver(
          forName: notification,
          object: nil,
          queue: .main
        ) { _ in
          handler()
        }
      }

      if let notification = willEnterForegroundNotification, let handler = onEnterForeground {
        NotificationCenter.default.addObserver(
          forName: notification,
          object: nil,
          queue: .main
        ) { _ in
          handler()
        }
      }
    }
  }
#endif
