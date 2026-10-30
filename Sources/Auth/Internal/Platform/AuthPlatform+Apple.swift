#if canImport(Darwin)
  import ConcurrencyExtras
  public import Foundation
  import IssueReporting

  #if os(watchOS)
    import WatchKit
  #elseif canImport(UIKit)
    import UIKit
  #elseif canImport(AppKit)
    import AppKit
  #endif

  #if canImport(AuthenticationServices)
    public import AuthenticationServices
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

  #if canImport(AuthenticationServices)
    extension AuthClient {
      /// The URL scheme `ASWebAuthenticationSession` listens on to capture the OAuth callback.
      ///
      /// Takes the already-resolved redirect — see ``oauthRedirectURL(redirectTo:configured:)`` —
      /// rather than resolving it again, so this can only ever name the scheme of the URL the
      /// provider was actually given.
      ///
      /// Pure so the scheme extraction and the guidance message can both be covered without
      /// presenting a session.
      static func oauthCallbackScheme(for redirectURL: URL?) throws -> String {
        guard let scheme = redirectURL?.scheme else {
          throw AuthError.oauthFlowFailed(
            """
            Provide a redirect URL with a scheme, either through the `redirectTo` parameter \
            or globally through `AuthClient.Configuration.redirectToURL`.
            """
          )
        }
        return scheme
      }

      /// Reported when `ASWebAuthenticationSession` completes with neither a URL nor an error.
      static let oauthSessionContractViolation =
        "ASWebAuthenticationSession returned neither a URL nor an error."

      /// Maps the `(url, error)` pair `ASWebAuthenticationSession` reports onto a result, favouring
      /// the error when it somehow reports both.
      ///
      /// Returns `nil` for the combination it documents as impossible — neither value present —
      /// which the caller turns into ``oauthSessionContractViolation``. The reporting stays with
      /// the caller because driving `reportIssue` from a `@Test` function segfaults under
      /// `xcodebuild test` (SDK-435); keeping it out here is what lets this be tested directly.
      static func oauthCallbackResult(url: URL?, error: (any Error)?) -> Result<URL, any Error>? {
        if let error { return .failure(error) }
        if let url { return .success(url) }
        return nil
      }
    }

    extension AuthPlatform {
      /// `ASWebAuthenticationSession.presentationContextProvider` is weak. Hold the returned
      /// provider until the session completes.
      @MainActor
      static func installDefaultPresentationAnchor(
        on session: ASWebAuthenticationSession
      ) -> AnyObject? {
        #if os(tvOS) || os(watchOS)
          return nil
        #else
          guard session.presentationContextProvider == nil else { return nil }
          let provider = DefaultPresentationContextProvider()
          session.presentationContextProvider = provider
          return provider
        #endif
      }
    }

    #if !os(tvOS) && !os(watchOS)
      @MainActor
      final class DefaultPresentationContextProvider: NSObject,
        ASWebAuthenticationPresentationContextProviding
      {
        func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
          ASPresentationAnchor()
        }
      }
    #endif
  #endif
#endif
