import Foundation

enum AppLifecycleEvent: Hashable, Sendable {
  case foreground
  case background
  case protectedDataDidBecomeAvailable
}

struct AuthPlatform: Sendable {
  /// `true` where the system can run the app in the background, where auto refresh pauses. Only
  /// there does a client that observes the lifecycle wait for the first lifecycle event before
  /// auto refresh starts. Elsewhere the client is in the foreground from the start, so a blocked
  /// main thread cannot hold auto refresh back.
  var hasBackgroundState: Bool

  /// Yields `.foreground` or `.background` for the current state first, then each change in the
  /// order the system posts it.
  var lifecycleEvents: @Sendable () async -> AsyncStream<AppLifecycleEvent>

  var openURL: @MainActor @Sendable (_ url: URL) throws -> Void

  var makeDefaultLocalStorage: @Sendable () -> any AuthLocalStorage
}
