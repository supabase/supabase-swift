#if !canImport(Darwin)
  import Foundation

  extension AuthPlatform {
    static let live = AuthPlatform(
      hasBackgroundState: false,
      lifecycleEvents: {
        let (events, continuation) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
        continuation.yield(.foreground)
        continuation.finish()
        return events
      }
    )

    static var defaultStorage: any AuthStorage { InMemoryAuthStorage() }
  }
#endif
