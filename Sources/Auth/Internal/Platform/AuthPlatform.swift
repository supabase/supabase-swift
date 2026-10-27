import Foundation

enum AppLifecycleEvent: Hashable, Sendable {
  case foreground
  case background
  case protectedDataDidBecomeAvailable
}

struct AuthPlatform: Sendable {
  /// Yields `.foreground` or `.background` for the current state first, then each change in the
  /// order the system posts it.
  var lifecycleEvents: @MainActor @Sendable () -> AsyncStream<AppLifecycleEvent>

  var openURL: @MainActor @Sendable (_ url: URL) throws -> Void

  var makeDefaultLocalStorage: @Sendable () -> any AuthLocalStorage
}
