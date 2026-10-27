#if !canImport(Darwin)
  import Foundation

  extension AuthPlatform {
    static let live = AuthPlatform(
      lifecycleEvents: {
        let (events, continuation) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
        continuation.yield(.foreground)
        continuation.finish()
        return events
      },
      openURL: { _ in
        throw AuthError.oauthFlowFailed(
          """
          This platform cannot open a URL. Pass a `launchURL` closure to \
          `linkIdentity(provider:scopes:redirectTo:queryParams:launchURL:)`.
          """
        )
      },
      makeDefaultLocalStorage: { EphemeralLocalStorage() }
    )
  }
#endif
