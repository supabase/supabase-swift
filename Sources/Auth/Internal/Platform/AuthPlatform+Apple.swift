#if canImport(Darwin)
  import ConcurrencyExtras
  public import Foundation

  #if os(watchOS)
    import WatchKit
  #elseif canImport(UIKit)
    import UIKit
  #elseif canImport(AppKit)
    import AppKit
  #endif

  extension AuthPlatform {
    static let live = AuthPlatform(
      hasBackgroundState: hasBackgroundState,
      lifecycleEvents: { await MainActor.run { observeInPostingOrder(lifecycleNotifications) } }
    )

    static var defaultLocalStorage: any AuthLocalStorage { KeychainLocalStorage() }

    #if os(watchOS) || canImport(UIKit)
      private static let hasBackgroundState = true
    #else
      private static let hasBackgroundState = false
    #endif

    /// A cold launch into the foreground posts `didBecomeActive` but not `willEnterForeground`.
    @MainActor
    private static var lifecycleNotifications: [(Notification.Name, AppLifecycleEvent)] {
      #if os(watchOS)
        [
          (WKApplication.willEnterForegroundNotification, .foreground),
          (WKApplication.didBecomeActiveNotification, .foreground),
          (WKApplication.didEnterBackgroundNotification, .background),
        ]
      #elseif canImport(UIKit)
        [
          (UIApplication.willEnterForegroundNotification, .foreground),
          (UIApplication.didBecomeActiveNotification, .foreground),
          (UIApplication.didEnterBackgroundNotification, .background),
          (
            UIApplication.protectedDataDidBecomeAvailableNotification,
            .protectedDataDidBecomeAvailable
          ),
        ]
      #elseif canImport(AppKit)
        [(NSApplication.didBecomeActiveNotification, .foreground)]
      #else
        []
      #endif
    }

    @MainActor
    private static var currentLifecycleState: AppLifecycleEvent {
      #if os(watchOS)
        WKApplication.shared().applicationState == .background ? .background : .foreground
      #elseif canImport(UIKit)
        // An app extension has no shared UIApplication.
        guard !Bundle.main.bundlePath.hasSuffix(".appex") else { return .foreground }
        return UIApplication.shared.applicationState == .background ? .background : .foreground
      #else
        .foreground
      #endif
    }

    @MainActor
    private static func observeInPostingOrder(
      _ notifications: [(Notification.Name, AppLifecycleEvent)]
    ) -> AsyncStream<AppLifecycleEvent> {
      let (events, continuation) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
      let observers = UncheckedSendable(
        notifications.map { name, event in
          NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
            continuation.yield(event)
          }
        }
      )
      continuation.onTermination = { _ in
        for observer in observers.value {
          NotificationCenter.default.removeObserver(observer)
        }
      }
      continuation.yield(currentLifecycleState)
      return events
    }
  }
#endif
